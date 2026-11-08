import XCTest
@testable import Akinti

/// Çok bağlantılı indirme, duraklat/devam ve hız sınırı testleri (yerel sunucu, ağ gerekmez).
final class SegmentTests: XCTestCase {
    private var server: Process!
    private var root: URL!
    private var base = ""
    private let expected = Data((0..<8192).flatMap { _ in (0...255).map { UInt8($0) } })

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let portFile = root.appendingPathComponent("port")
        server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("server.py").path, portFile.path]
        try server.run()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: portFile.path) { try await Task.sleep(nanoseconds: 20_000_000) }
        base = "http://127.0.0.1:\(try String(contentsOf: portFile))"
        HTTPJob.minimumSegmentSize = 64 * 1024
    }

    override func tearDown() {
        server.terminate(); server.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
        HTTPJob.minimumSegmentSize = 1 << 20
    }

    private func stats() throws -> [String: Int] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: URL(string: "\(base)/stats")!)) as! [String: Int]
    }

    @MainActor private func waitUntil(_ timeout: Double = 20, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testSplitCoversWholeFile() {
        HTTPJob.minimumSegmentSize = 1 << 20
        let parts = HTTPJob.split(size: 10_000_000, connections: 8)
        XCTAssertEqual(parts.count, 8)
        XCTAssertEqual(parts.first?.start, 0)
        XCTAssertEqual(parts.last?.end, 9_999_999)
        XCTAssertEqual(parts.map(\.length).reduce(0, +), 10_000_000)
        for (a, b) in zip(parts, parts.dropFirst()) { XCTAssertEqual(a.end + 1, b.start) }
        XCTAssertEqual(HTTPJob.split(size: 500_000, connections: 8).count, 1) // küçük dosya bölünmez
    }

    @MainActor func testParallelConnectionsProduceIdenticalFile() async throws {
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        store.preferences.connectionsPerDownload = 8
        XCTAssertTrue(store.add("\(base)/r/slow-file"))
        try await waitUntil { store.items[0].state == "İndiriliyor" && (store.items[0].segments?.count ?? 0) > 1 }
        XCTAssertEqual(store.items[0].segments?.count, 8)
        try await waitUntil { store.items[0].state == "Tamamlandı" }
        XCTAssertEqual(store.items[0].state, "Tamamlandı")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.items[0].saved)), expected)
        XCTAssertEqual(store.items[0].name, "sample.bin")
        XCTAssertGreaterThan(try stats()["max_active"] ?? 0, 1, "sunucu aynı anda birden fazla bağlantı görmeli")
    }

    @MainActor func testPauseKeepsSegmentProgressAndResumes() async throws {
        let state = root.appendingPathComponent("state")
        let store = DownloadStore(directory: state, destination: root.appendingPathComponent("files"))
        store.preferences.connectionsPerDownload = 4
        XCTAssertTrue(store.add("\(base)/r/slow-pause"))
        let id = store.items[0].id
        try await waitUntil { store.items[0].received > 300_000 }
        store.pause(id)
        XCTAssertEqual(store.items[0].state, "Duraklatılıyor")
        try await waitUntil { store.items[0].state == "Duraklatıldı" }
        let pausedAt = store.items[0].received
        XCTAssertGreaterThan(pausedAt, 0)
        XCTAssertLessThan(pausedAt, Int64(expected.count))
        XCTAssertEqual(store.items[0].segments?.count, 4)

        // Kayıttan yeniden açılınca da ilerleme korunur.
        let restored = DownloadStore(directory: state, destination: root.appendingPathComponent("files"))
        XCTAssertEqual(restored.items[0].received, pausedAt)
        restored.start(id)
        try await waitUntil { restored.items[0].state == "Tamamlandı" }
        XCTAssertEqual(restored.items[0].state, "Tamamlandı")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.items[0].saved)), expected)
        // Devam baştan başlamadı: sunucunun gönderdiği toplam, dosyanın iki katından az.
        XCTAssertLessThan(try stats()["bytes"] ?? .max, expected.count * 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.appendingPathComponent("partial/\(id.uuidString).part").path))
    }

    @MainActor func testServerWithoutRangesFallsBackToSingleConnection() async throws {
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        XCTAssertTrue(store.add("\(base)/plain"))
        try await waitUntil { store.items[0].state == "Tamamlandı" }
        XCTAssertEqual(store.items[0].segments, nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.items[0].saved)), expected)
        XCTAssertEqual(try stats()["max_active"], 1)
    }

    @MainActor func testSpeedLimitSlowsDownloads() async throws {
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        store.preferences.speedLimitKB = 1024 // 1 MB/sn; dosya 2 MB
        XCTAssertEqual(store.limiter.bytesPerSecond, 1024 * 1024)
        let started = Date()
        XCTAssertTrue(store.add("\(base)/r/limited"))
        try await waitUntil(30) { store.items[0].state == "Tamamlandı" }
        XCTAssertEqual(store.items[0].state, "Tamamlandı")
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 1.4)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.items[0].saved)), expected)
    }
}
