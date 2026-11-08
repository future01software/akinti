import XCTest
@testable import Akinti

final class FeatureTests: XCTestCase {
    func testCategoriesFromExtension() {
        XCTAssertEqual(FileCategory.of("arsiv.ZIP"), .compressed)
        XCTAssertEqual(FileCategory.of("film.mkv"), .video)
        XCTAssertEqual(FileCategory.of("sarki.flac"), .music)
        XCTAssertEqual(FileCategory.of("rapor.pdf"), .documents)
        XCTAssertEqual(FileCategory.of("foto.heic"), .images)
        XCTAssertEqual(FileCategory.of("Kurulum.dmg"), .programs)
        XCTAssertEqual(FileCategory.of("index"), .other)
    }

    func testLinkExtractionIgnoresJunk() {
        let text = "Şuradan indir: <https://example.org/a.zip>\nftp://x.org/b.zip\nhttp://example.org/c.mp4, olmayan"
        XCTAssertEqual(DownloadStore.links(in: text).map(\.absoluteString), ["https://example.org/a.zip", "http://example.org/c.mp4"])
    }

    @MainActor func testDownloadLaterAndPausingQueuedItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        XCTAssertTrue(store.add("https://example.org/later.zip", startPaused: true))
        XCTAssertEqual(store.items[0].state, "Duraklatıldı")
        XCTAssertNotNil(store.items[0].addedAt)
        XCTAssertEqual(store.items[0].category, .compressed)
        XCTAssertTrue(store.add("https://example.org/planned.pdf", scheduledAt: .distantFuture))
        store.pause(store.items[1].id)
        XCTAssertEqual(store.items[1].state, "Duraklatıldı")
        store.clearCompleted()
        XCTAssertEqual(store.items.count, 2)
    }

    func testOldSettingsFileStillDecodes() throws {
        let json = #"{"destinationPath":"/tmp/x","simultaneousDownloads":4,"retryLimit":2,"appearance":"dark"}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.simultaneousDownloads, 4)
        XCTAssertTrue(prefs.clipboardCapture)
        XCTAssertTrue(prefs.showMenuBarIcon)
        XCTAssertFalse(prefs.menuBarOnly)
        XCTAssertFalse(prefs.torrentSeeding)
        XCTAssertTrue(prefs.showProgressWindow)
    }

    @MainActor func testMenuBarPreferencesPersistAndNotify() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root, destination: root.appendingPathComponent("files"))
        let notified = expectation(forNotification: DownloadStore.dockPolicyChanged, object: nil)
        store.preferences.menuBarOnly = true
        wait(for: [notified], timeout: 1)
        store.preferences.showMenuBarIcon = false
        let restored = DownloadStore(directory: root)
        XCTAssertTrue(restored.preferences.menuBarOnly)
        XCTAssertFalse(restored.preferences.showMenuBarIcon)
    }

    @MainActor func testLanguageSwitchesInstantly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let store = DownloadStore(directory: root, destination: root.appendingPathComponent("files"))
        store.preferences.language = "en"
        XCTAssertEqual(FileCategory.compressed.title, "Archives")
        XCTAssertEqual(L10n.state("Duraklatıldı"), "Paused")
        XCTAssertEqual(Format.eta(90), "1 min 30 s")
        store.preferences.language = "tr"
        XCTAssertEqual(FileCategory.compressed.title, "Arşivler")
        XCTAssertEqual(Format.eta(90), "1 dk 30 sn")
        XCTAssertEqual(DownloadStore(directory: root).preferences.language, "tr")
    }

    @MainActor func testProgressWindowRequests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root, destination: root.appendingPathComponent("files"))
        XCTAssertTrue(store.preferences.showProgressWindow)
        XCTAssertTrue(store.add("http://127.0.0.1:9/a.zip", scheduledAt: .distantFuture)) // planlı: pencere yok
        XCTAssertTrue(store.popupRequests.isEmpty)
        XCTAssertTrue(store.add("http://127.0.0.1:9/b.zip", startPaused: true))           // sonra indir: pencere yok
        XCTAssertTrue(store.popupRequests.isEmpty)
        store.preferences.simultaneousDownloads = 1
        store.pauseAll()
        XCTAssertTrue(store.add("http://127.0.0.1:9/c.zip\nhttp://127.0.0.1:9/d.zip"))   // hemen indirilecek: 2 pencere
        XCTAssertEqual(store.popupRequests.count, 2)
        store.popupRequests = []
        XCTAssertTrue(store.add((1...4).map { "http://127.0.0.1:9/\($0).zip" }.joined(separator: "\n"))) // 4 > 3: pencere yok
        XCTAssertTrue(store.popupRequests.isEmpty)
        store.preferences.showProgressWindow = false
        XCTAssertTrue(store.add("http://127.0.0.1:9/e.zip"))
        XCTAssertTrue(store.popupRequests.isEmpty)
        store.pauseAll()
    }
}
