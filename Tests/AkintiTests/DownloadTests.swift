import XCTest
@testable import Akinti

final class DownloadTests: XCTestCase {
    @MainActor func testHTTPDownloadQueueErrorsAndPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let portFile = root.appendingPathComponent("port")
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("server.py").path, portFile.path]
        try server.run()
        defer { server.terminate(); server.waitUntilExit(); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: portFile.path) { try await Task.sleep(nanoseconds: 20_000_000) }
        let port = try String(contentsOf: portFile)
        let base = "http://127.0.0.1:\(port)"
        let store = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        store.limit = 1
        XCTAssertFalse(store.add("file:///etc/hosts"))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.add("\(base)/slow\n\(base)/file\n\(base)/missing"))
        XCTAssertEqual(store.items.filter { $0.state == "İndiriliyor" }.count, 1)
        XCTAssertEqual(store.items.filter { $0.state == "Bekliyor" }.count, 2)
        let id = store.items[0].id
        try await Task.sleep(nanoseconds: 150_000_000)
        store.pause(id)
        for _ in 0..<100 where store.items[0].state != "Duraklatıldı" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items[0].state, "Duraklatıldı")
        store.start(id)
        for _ in 0..<500 where store.items.contains(where: { ["Bekliyor", "İndiriliyor"].contains($0.state) }) { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items.filter { $0.state == "Tamamlandı" }.count, 2)
        XCTAssertEqual(store.items[2].state, "Hata")
        XCTAssertTrue(store.items[2].error?.contains("404") == true)
        XCTAssertNil(store.items[2].saved)
        let first = try XCTUnwrap(store.items[0].saved)
        let second = try XCTUnwrap(store.items[1].saved)
        XCTAssertNotEqual(first, second)
        let expected = Data((0..<8192).flatMap { _ in (0...255).map { UInt8($0) } })
        XCTAssertEqual(try Data(contentsOf: first), expected)
        XCTAssertEqual(try Data(contentsOf: second), expected)
        let restored = DownloadStore(directory: root.appendingPathComponent("state"), destination: root.appendingPathComponent("files"))
        XCTAssertEqual(restored.items.count, 3)
        XCTAssertEqual(restored.items[0].saved, first)
        let chosenFolder = root.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: chosenFolder, withIntermediateDirectories: true)
        XCTAssertTrue(store.chooseDestination(chosenFolder))
        XCTAssertTrue(store.add("\(base)/flaky", scheduledAt: Date().addingTimeInterval(1)))
        let plannedID = try XCTUnwrap(store.items.last?.id)
        XCTAssertEqual(store.items.last?.state, "Planlandı")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.items.last?.state, "Planlandı")
        for _ in 0..<600 where store.items.last?.state != "Tamamlandı" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items.last?.state, "Tamamlandı")
        XCTAssertEqual(store.items.last?.retryCount, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.items.last?.saved)), expected)
        XCTAssertEqual(store.items.last?.saved?.deletingLastPathComponent().path, chosenFolder.path)
        store.remove(plannedID)
        store.preferences.retryLimit = 0
        XCTAssertTrue(store.add("\(base)/unavailable"))
        for _ in 0..<100 where store.items.last?.state == "İndiriliyor" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.items.last?.state, "Hata")
        XCTAssertNil(store.items.last?.retryAt)
        XCTAssertNil(store.items.last?.saved)
        store.remove(id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }
}
