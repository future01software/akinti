import XCTest
@testable import Akinti

final class VideoTests: XCTestCase {
    override func setUp() {
        VideoEngine.overrideExecutable = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fake-yt-dlp")
    }
    override func tearDown() { VideoEngine.overrideExecutable = nil }

    func testVideoPageDetection() {
        XCTAssertTrue(VideoEngine.isVideoPage(URL(string: "https://www.youtube.com/watch?v=abc")!))
        XCTAssertTrue(VideoEngine.isVideoPage(URL(string: "https://youtu.be/abc")!))
        XCTAssertTrue(VideoEngine.isVideoPage(URL(string: "https://vimeo.com/123")!))
        XCTAssertFalse(VideoEngine.isVideoPage(URL(string: "https://example.org/file.zip")!))
        XCTAssertFalse(VideoEngine.isVideoPage(URL(string: "https://notyoutube.com/x")!))
        XCTAssertFalse(VideoEngine.isVideoPage(URL(string: "https://vimeo.com/setup.dmg")!))
    }

    func testQualityArguments() {
        XCTAssertEqual(VideoQuality.p1080.arguments(hasFFmpeg: true), ["-f", "bv*[height<=1080]+ba/b[height<=1080]/b", "--merge-output-format", "mp4", "-S", "res,vcodec:h264,acodec:m4a"])
        XCTAssertEqual(VideoQuality.p720.arguments(hasFFmpeg: false), ["-f", "b[height<=720]/b", "-S", "res,vcodec:h264,acodec:m4a"])
        XCTAssertEqual(VideoQuality.audioMP3.arguments(hasFFmpeg: true), ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"])
        XCTAssertEqual(VideoQuality.audioMP3.arguments(hasFFmpeg: false), ["-f", "ba[ext=m4a]/ba/b"])
    }

    func testProbeReadsTitleAndErrors() async throws {
        let info = try await VideoEngine.probe(URL(string: "https://youtu.be/abc")!)
        XCTAssertEqual(info.title, "Test Video")
        XCTAssertEqual(info.maxHeight, 1080)
        XCTAssertEqual(info.duration, 125)
        do { _ = try await VideoEngine.probe(URL(string: "https://youtu.be/missing")!); XCTFail("hata bekleniyordu") }
        catch { XCTAssertEqual(error.localizedDescription, "[youtube] abc: Video unavailable") }
    }

    @MainActor func testVideoDownloadPauseResumeAndError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        store.preferences.retryLimit = 0

        XCTAssertTrue(store.add("https://www.youtube.com/watch?v=slow", quality: .p720, titles: [URL(string: "https://www.youtube.com/watch?v=slow")!: "Test Video"]))
        let id = store.items[0].id
        XCTAssertEqual(store.items[0].isVideo, true)
        XCTAssertEqual(store.items[0].name, "Test Video")
        XCTAssertEqual(store.items[0].category, .video)
        XCTAssertEqual(store.items[0].state, "İndiriliyor")
        for _ in 0..<100 where store.items[0].received == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(store.items[0].received, 0)
        XCTAssertEqual(store.items[0].total, 4000)

        store.pause(id)
        XCTAssertEqual(store.items[0].state, "Duraklatılıyor")
        store.start(id) // süreç kapanmadan ikinci yt-dlp başlamamalı
        XCTAssertEqual(store.items[0].state, "Duraklatılıyor")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(store.items[0].state, "Duraklatıldı")
        XCTAssertNil(store.items[0].saved)

        store.start(id)
        for _ in 0..<300 where store.items[0].state != "Tamamlandı" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items[0].state, "Tamamlandı")
        XCTAssertEqual(store.items[0].name, "Test Video [abc123].mp4")
        XCTAssertEqual(store.items[0].total, 4000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.items[0].saved).path))

        XCTAssertTrue(store.add("https://youtu.be/missing", quality: .audioM4A))
        XCTAssertEqual(store.items[1].category, .music)
        for _ in 0..<200 where store.items[1].state == "İndiriliyor" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items[1].state, "Hata")
        XCTAssertEqual(store.items[1].error, "[youtube] abc: Video unavailable")

        // Dosya modu: aynı site bağlantısı video olarak işlenmez.
        XCTAssertTrue(store.add("https://youtu.be/x", startPaused: true, mode: .file))
        XCTAssertNil(store.items[2].isVideo)
    }

    @MainActor func testMissingEngineShowsInstallHint() {
        VideoEngine.overrideExecutable = URL(fileURLWithPath: "/nonexistent/yt-dlp")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root, destination: root.appendingPathComponent("files"))
        XCTAssertTrue(store.add("https://youtu.be/abc"))
        XCTAssertEqual(store.items[0].state, "Hata")
    }

    @MainActor func testQuitStopsRunningVideoJobs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        XCTAssertTrue(store.add("https://youtu.be/slow"))
        for _ in 0..<100 where store.items[0].received == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        store.stopVideoJobs()
        XCTAssertEqual(store.items[0].state, "Duraklatıldı")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(store.items[0].state, "Duraklatıldı")
        XCTAssertNil(store.items[0].saved)
        // Kapatıldıktan sonra yeniden başlatılabilir ve tamamlanır.
        store.start(store.items[0].id)
        for _ in 0..<300 where store.items[0].state != "Tamamlandı" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items[0].state, "Tamamlandı")
    }

    func testPlaylistDetectionAndEntries() async throws {
        let mixed = URL(string: "https://www.youtube.com/watch?v=a1&list=PL123")!
        let pure = URL(string: "https://www.youtube.com/playlist?list=PL123")!
        XCTAssertTrue(VideoEngine.isPlaylist(mixed))
        XCTAssertTrue(VideoEngine.isPlaylist(pure))
        XCTAssertTrue(VideoEngine.isPlaylist(URL(string: "https://soundcloud.com/artist/sets/album")!))
        XCTAssertFalse(VideoEngine.isPlaylist(URL(string: "https://www.youtube.com/watch?v=a1")!))
        XCTAssertTrue(VideoEngine.hasSingleVideo(mixed))
        XCTAssertFalse(VideoEngine.hasSingleVideo(pure))

        let info = try await VideoEngine.probe(pure)
        XCTAssertTrue(info.isPlaylist)
        XCTAssertEqual(info.title, "Test Listesi")
        XCTAssertEqual(info.entries.map(\.title), ["Bir", "İki", "Üç"])
        XCTAssertEqual(info.entries.first?.url.absoluteString, "https://www.youtube.com/watch?v=a1")
    }

    @MainActor func testPlaylistEntriesBecomeSeparateDownloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        let info = try await VideoEngine.probe(URL(string: "https://www.youtube.com/playlist?list=PL123")!)
        let titles = Dictionary(uniqueKeysWithValues: info.entries.map { ($0.url, $0.title) })
        XCTAssertTrue(store.add(info.entries.map(\.url.absoluteString).joined(separator: "\n"), startPaused: true, titles: titles))
        XCTAssertEqual(store.items.map(\.name), ["Bir", "İki", "Üç"])
        XCTAssertTrue(store.items.allSatisfy { $0.isVideo == true && $0.state == "Duraklatıldı" })
    }
}
