import XCTest
@testable import Akinti

final class PreferencesTests: XCTestCase {
    @MainActor func testPreferencesPersistAndDoNotRedirectExistingDownloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = root.appendingPathComponent("original")
        let chosen = root.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state")
        let store = DownloadStore(directory: state, destination: original)
        XCTAssertTrue(store.add("https://example.org/first.zip", scheduledAt: .distantFuture))
        XCTAssertTrue(store.chooseDestination(chosen))
        store.limit = 6
        store.preferences.retryLimit = 0
        store.preferences.appearance = "dark"
        XCTAssertTrue(store.add("https://example.org/second.zip", scheduledAt: .distantFuture))
        XCTAssertEqual(store.items[0].destinationFolder?.path, original.path)
        XCTAssertEqual(store.items[1].destinationFolder?.path, chosen.path)
        XCTAssertFalse(store.chooseDestination(root.appendingPathComponent("missing")))
        XCTAssertEqual(store.destinationFolder.path, chosen.path)

        let restored = DownloadStore(directory: state)
        XCTAssertEqual(restored.limit, 6)
        XCTAssertEqual(restored.preferences.retryLimit, 0)
        XCTAssertEqual(restored.preferences.appearance, "dark")
        XCTAssertEqual(restored.destinationFolder.path, chosen.path)
        XCTAssertEqual(restored.items[0].destinationFolder?.path, original.path)
        XCTAssertEqual(restored.items[1].destinationFolder?.path, chosen.path)
    }
}
