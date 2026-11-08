import XCTest
@testable import Akinti

/// Gerçek torrent indirmeleri: yerel tracker + aria2 seeder + Akıntı (aria2). İnternet gerekmez.
/// aria2 kurulu değilse atlanır.
final class TorrentTests: XCTestCase {
    private var root: URL!
    private var processes: [Process] = []
    private var infohash = ""
    private var tracker = ""
    private let seederPort = Int.random(in: 30000...40000)

    override func setUp() async throws {
        guard let aria2 = TorrentEngine.executable else { throw XCTSkip("aria2 kurulu değil") }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        fixture.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("torrent_fixture.py").path, root.path, String(seederPort)]
        try fixture.run(); processes.append(fixture)
        let info = root.appendingPathComponent("fixture.json")
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: info.path) { try await Task.sleep(nanoseconds: 20_000_000) }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: info)) as! [String: String]
        infohash = json["infohash"]!; tracker = json["tracker"]!

        // Seeder: dosyayı doğrular (-V) ve süresiz paylaşır.
        let seeder = Process()
        seeder.executableURL = aria2
        seeder.arguments = ["-V", "--seed-ratio=0.0", "--enable-dht=false", "--bt-enable-lpd=false", "--listen-port=\(seederPort)",
                            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)", "--quiet", "--console-log-level=error",
                            "-d", root.appendingPathComponent("seed").path, root.appendingPathComponent("test.torrent").path]
        seeder.standardOutput = FileHandle.nullDevice
        try seeder.run(); processes.append(seeder)
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    override func tearDown() {
        for p in processes where p.isRunning { p.terminate(); p.waitUntilExit() }
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    @MainActor private func makeStore() -> DownloadStore {
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        store.preferences.retryLimit = 0
        store.preferences.showProgressWindow = false
        store.torrentEngine.extraArguments = ["--enable-dht=false", "--bt-enable-lpd=false", "--listen-port=\(seederPort + 1)",
                                              "--bt-tracker-connect-timeout=5", "--bt-tracker-timeout=5"]
        return store
    }

    @MainActor private func waitUntil(_ timeout: Double, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try await Task.sleep(nanoseconds: 100_000_000) }
    }

    private var expected: Data { (try? Data(contentsOf: root.appendingPathComponent("seed/akinti-test.bin"))) ?? Data() }

    @MainActor func testTorrentFileDownloadsWithPauseAndResume() async throws {
        let store = makeStore()
        defer { store.prepareForQuit() }
        store.preferences.speedLimitKB = 256 // 2 MB ≈ 8 sn: duraklatmaya zaman kalsın
        XCTAssertTrue(store.addTorrentFile(root.appendingPathComponent("test.torrent")))
        let id = store.items[0].id
        XCTAssertEqual(store.items[0].category, .torrents)
        try await waitUntil(30) { store.items[0].received > 0 }
        XCTAssertEqual(store.items[0].state, "İndiriliyor")
        XCTAssertEqual(store.items[0].name, "akinti-test.bin")
        XCTAssertEqual(store.items[0].total, 2 * 1024 * 1024)
        XCTAssertEqual(store.items[0].pieceMap?.count, 32) // 2 MB / 64 KB = 32 parça

        store.pause(id)
        try await waitUntil(10) { store.items[0].state == "Duraklatıldı" }
        XCTAssertEqual(store.items[0].state, "Duraklatıldı")
        let pausedAt = store.items[0].received
        XCTAssertLessThan(pausedAt, 2 * 1024 * 1024)

        store.preferences.speedLimitKB = 0
        store.start(id)
        try await waitUntil(60) { store.items[0].state == "Tamamlandı" }
        XCTAssertEqual(store.items[0].state, "Tamamlandı", store.items[0].error ?? "")
        let saved = try XCTUnwrap(store.items[0].saved)
        XCTAssertEqual(saved.lastPathComponent, "akinti-test.bin")
        XCTAssertEqual(try Data(contentsOf: saved), expected)
    }

    @MainActor func testMagnetLinkDownloads() async throws {
        let store = makeStore()
        defer { store.prepareForQuit() }
        let tr = tracker.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let magnet = "magnet:?xt=urn:btih:\(infohash)&dn=akinti-test.bin&tr=\(tr)"
        XCTAssertTrue(store.add(magnet))
        XCTAssertEqual(store.items[0].isTorrent, true)
        XCTAssertEqual(store.items[0].name, "akinti-test.bin")
        try await waitUntil(60) { store.items[0].state == "Tamamlandı" || store.items[0].state == "Hata" }
        XCTAssertEqual(store.items[0].state, "Tamamlandı", store.items[0].error ?? "")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.items[0].saved)), expected)
    }
}

final class TorrentHelperTests: XCTestCase {
    func testMagnetParsing() {
        let magnet = URL(string: "magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01&dn=Ubuntu%2024.04&tr=udp%3A%2F%2Ftracker")!
        XCTAssertTrue(TorrentEngine.isMagnet(magnet))
        XCTAssertTrue(TorrentEngine.isTorrentLink(URL(string: "https://example.org/linux.torrent")!))
        XCTAssertFalse(TorrentEngine.isTorrentLink(URL(string: "https://example.org/linux.iso")!))
        XCTAssertEqual(TorrentEngine.displayName(magnet), "Ubuntu 24.04")
        XCTAssertEqual(TorrentEngine.displayName(URL(string: "magnet:?xt=urn:btih:abcdef0123456789")!), "Torrent abcdef012345")
        XCTAssertEqual(DownloadStore.links(in: "bak: \(magnet.absoluteString) ve https://a.org/x.zip").count, 2)
    }

    func testPieceMapFromBitfield() {
        // 8 parça: 1111 0000 -> ilk yarı inmiş
        XCTAssertEqual(TorrentEngine.pieceMap(bitfield: "f0", pieces: 8, bins: 2), [1, 0])
        XCTAssertEqual(TorrentEngine.pieceMap(bitfield: "a0", pieces: 4, bins: 4), [1, 0, 1, 0])
        XCTAssertEqual(TorrentEngine.pieceMap(bitfield: "c0", pieces: 4, bins: 2), [1, 0])
        XCTAssertEqual(TorrentEngine.pieceMap(bitfield: "", pieces: 3, bins: 64).count, 3)
    }

    @MainActor func testTorrentLinksAreDetectedOnAdd() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root, destination: root.appendingPathComponent("files"))
        XCTAssertTrue(store.add("magnet:?xt=urn:btih:abc&dn=Film\nhttps://example.org/a.torrent\nhttps://example.org/b.torrent", startPaused: true))
        XCTAssertEqual(store.items.map { $0.isTorrent == true }, [true, true, true])
        XCTAssertTrue(store.add("https://example.org/c.torrent", startPaused: true, mode: .file)) // Dosya modu: .torrent dosyasının kendisi
        XCTAssertNil(store.items.last?.isTorrent)
        XCTAssertFalse(store.addTorrentFile(root.appendingPathComponent("yok.torrent")))
    }
}
