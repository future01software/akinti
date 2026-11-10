import XCTest
@testable import Akinti

@MainActor
final class UpdaterTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("0.11.0", than: "0.10.3"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.99.9"))
        XCTAssertTrue(Updater.isNewer("0.10.10", than: "0.10.9"))
        XCTAssertFalse(Updater.isNewer("0.10.3", than: "0.10.3"))
        XCTAssertFalse(Updater.isNewer("0.10.2", than: "0.10.3"))
        XCTAssertFalse(Updater.isNewer("0.11.0", than: "0.11.0-dev"))
        XCTAssertTrue(Updater.isNewer("0.11.1", than: "0.11.0-dev"))
    }

    func testParsesGitHubRelease() throws {
        let json = #"""
        {"tag_name":"v0.11.0","html_url":"https://github.com/x/akinti/releases/tag/v0.11.0","body":"### Eklendi\n- güncelleyici","draft":false,"prerelease":false,
         "assets":[{"name":"Akinti-Chrome-Extension.zip","browser_download_url":"https://x/e.zip"},
                   {"name":"Akinti-macOS.zip","browser_download_url":"https://x/a.zip","digest":"sha256:abc"},
                   {"name":"Akinti-macOS.zip.sha256","browser_download_url":"https://x/a.zip.sha256"}]}
        """#
        let release = try XCTUnwrap(Updater.parseRelease(Data(json.utf8)))
        XCTAssertEqual(release.version, "0.11.0")
        XCTAssertEqual(release.zipURL.absoluteString, "https://x/a.zip")
        XCTAssertEqual(release.sha256, "sha256:abc")
        XCTAssertEqual(release.sha256FileURL?.absoluteString, "https://x/a.zip.sha256")
        XCTAssertNil(Updater.parseRelease(Data(json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true").utf8)))
        XCTAssertNil(Updater.parseRelease(Data(#"{"tag_name":"v1","assets":[]}"#.utf8)))
    }

    /// Sahte ama imzalı bir Akıntı.app paketi ve zip'i.
    private func fakeApp(version: String, bundleID: String = Updater.bundleID, marker: String) throws -> URL {
        let stage = root.appendingPathComponent("stage-\(UUID().uuidString)")
        let app = stage.appendingPathComponent("Akıntı.app/Contents")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho \(marker)\n".utf8).write(to: app.appendingPathComponent("MacOS/Akinti"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("MacOS/Akinti").path)
        let plist: [String: Any] = ["CFBundleExecutable": "Akinti", "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", stage.appendingPathComponent("Akıntı.app").path])
        let zip = root.appendingPathComponent("Akinti-\(version)-\(UUID().uuidString).zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", stage.appendingPathComponent("Akıntı.app").path, zip.path])
        return zip
    }

    /// Bundle önbelleğe alındığı için sürüm doğrudan Info.plist'ten okunur.
    private func version(of app: URL) -> String? {
        (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "\(tool) \(args)")
    }

    private var tempLeftovers: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []).filter { $0.hasPrefix("akinti-update-") }.count
    }

    func testValidatesDownloadedBundle() throws {
        let before = tempLeftovers
        let app = try Updater.unpackAndValidate(try fakeApp(version: "9.9.9", marker: "ok"), expectedVersion: "9.9.9")
        try FileManager.default.removeItem(at: app.deletingLastPathComponent())
        XCTAssertThrowsError(try Updater.unpackAndValidate(try fakeApp(version: "9.9.9", marker: "x"), expectedVersion: "9.9.8")) // sürüm uyuşmuyor
        XCTAssertThrowsError(try Updater.unpackAndValidate(try fakeApp(version: "9.9.9", bundleID: "com.kotu.app", marker: "x"), expectedVersion: "9.9.9"))
        XCTAssertEqual(tempLeftovers, before, "başarısız doğrulama geçici klasör bırakmamalı")
    }

    func testRemovesLeftovers() throws {
        let folder = root.appendingPathComponent("tmp"); try FileManager.default.createDirectory(at: folder.appendingPathComponent("akinti-update-1/Akıntı.app"), withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("akinti-update-2.sh"))
        try Data().write(to: folder.appendingPathComponent("baska-dosya.txt"))
        Updater.removeLeftovers(in: folder)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["baska-dosya.txt"])
    }

    /// Uçtan uca: indir (file://) → SHA-256 → aç ve doğrula → değiştirme betiği → hedef yeni sürümle değişir.
    func testInstallReplacesApplication() async throws {
        // Kurulu "eski" sürüm
        let installedFolder = root.appendingPathComponent("Applications"); try FileManager.default.createDirectory(at: installedFolder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", try fakeApp(version: "1.0.0", marker: "eski").path, installedFolder.path])
        let target = installedFolder.appendingPathComponent("Akıntı.app")
        // Yeni sürüm
        let zip = try fakeApp(version: "1.1.0", marker: "yeni")
        let updater = Updater()
        // Önce yanlış özetle: kurulmamalı
        await updater.install(Updater.Release(version: "1.1.0", notes: "", pageURL: zip, zipURL: zip, sha256: "sha256:" + String(repeating: "0", count: 64)),
                              appURL: target, relaunch: false)
        guard case .failed = updater.phase else { return XCTFail("yanlış özetle kurulmamalıydı: \(updater.phase)") }
        XCTAssertEqual(version(of: target), "1.0.0")
        // Doğru özetle: değiştirme betiği çalışır (süreç kapanmayı beklemez; relaunch=false)
        await updater.install(Updater.Release(version: "1.1.0", notes: "", pageURL: zip, zipURL: zip, sha256: "sha256:" + (try ToolManager.sha256(of: zip))),
                              appURL: target, relaunch: false)
        XCTAssertEqual(updater.phase, .installing)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, version(of: target) != "1.1.0" { try await Task.sleep(nanoseconds: 200_000_000) }
        XCTAssertEqual(version(of: target), "1.1.0")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("Contents/MacOS/Akinti"), encoding: .utf8), "#!/bin/sh\necho yeni\n")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: installedFolder.path)
        XCTAssertEqual(leftovers, ["Akıntı.app"], "yedek silinmeli")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(tempLeftovers, 0, "betik geçici klasörü silmeli")
    }
}
