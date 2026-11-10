import XCTest
import AkintiShared
@testable import Akinti

final class BrowserBridgeTests: XCTestCase {
    func testAkintiLinkRoundTripAndSafety() throws {
        let link = AkintiLink(urls: [URL(string: "https://x.org/a b.zip?x=1&y=2+3")!, URL(string: "magnet:?xt=urn:btih:abc&dn=İsim")!],
                              referrer: "https://x.org/sayfa?q=ç", userAgent: "Mozilla/5.0 (Macintosh)", mode: "video")
        let url = try XCTUnwrap(link.url)
        XCTAssertEqual(url.scheme, "akinti")
        XCTAssertEqual(AkintiLink.parse(url), link)
        // İzin verilmeyen şemalar ayıklanır; hiç geçerli bağlantı kalmazsa istek reddedilir.
        XCTAssertNil(AkintiLink.parse(URL(string: "akinti://add?u=javascript:alert(1)&u=file:///etc/passwd")!))
        XCTAssertEqual(AkintiLink.parse(URL(string: "akinti://add?u=file:///etc/passwd&u=https://ok.org/a.zip")!)?.urls.map(\.absoluteString), ["https://ok.org/a.zip"])
        XCTAssertNil(AkintiLink.parse(URL(string: "akinti://delete?u=https://ok.org/a.zip")!))
        XCTAssertNil(AkintiLink.parse(URL(string: "https://ok.org/a.zip")!))
    }

    func testNativeMessageFraming() throws {
        let data = try NativeMessage.encode(["type": "ping"])
        XCTAssertEqual(Int(data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian), data.count - 4)
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(data); try pipe.fileHandleForWriting.close()
        XCTAssertEqual(try NativeMessage.read(from: pipe.fileHandleForReading)?["type"] as? String, "ping")
        XCTAssertNil(try NativeMessage.read(from: pipe.fileHandleForReading)) // akış bitti
    }

    /// Gerçek köprü programı: ping ve add mesajlarına doğru yanıt verir (Akıntı açılmaz: DRYRUN).
    func testBridgeExecutable() throws {
        let bridge = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("akinti-bridge")
        guard FileManager.default.isExecutableFile(atPath: bridge.path) else { throw XCTSkip("akinti-bridge derlenmemiş") }
        let process = Process()
        process.executableURL = bridge
        process.environment = ["AKINTI_BRIDGE_DRYRUN": "1"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(try NativeMessage.encode(["type": "ping"]))
        input.fileHandleForWriting.write(try NativeMessage.encode(["type": "add", "urls": ["https://x.org/a.zip", "javascript:x"], "referrer": "https://x.org/"]))
        input.fileHandleForWriting.write(try NativeMessage.encode(["type": "add", "urls": ["file:///etc/passwd"]]))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let replies = [try NativeMessage.read(from: output.fileHandleForReading), try NativeMessage.read(from: output.fileHandleForReading),
                       try NativeMessage.read(from: output.fileHandleForReading)]
        XCTAssertEqual(replies[0]?["ok"] as? Bool, true)
        XCTAssertNotNil(replies[0]?["version"])
        XCTAssertEqual(replies[1]?["ok"] as? Bool, true)
        XCTAssertEqual(replies[2]?["ok"] as? Bool, false)
        let opened = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let link = try XCTUnwrap(AkintiLink.parse(XCTUnwrap(URL(string: opened))))
        XCTAssertEqual(link.urls.map(\.absoluteString), ["https://x.org/a.zip"])
        XCTAssertEqual(link.referrer, "https://x.org/")
    }

    func testRegistersOnlyInstalledBrowsers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); BrowserBridge.applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
        BrowserBridge.applicationSupport = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Google/Chrome"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("BraveSoftware/Brave-Browser"), withIntermediateDirectories: true)
        let bridge = URL(fileURLWithPath: "/Applications/Akıntı.app/Contents/Helpers/akinti-bridge")
        XCTAssertEqual(BrowserBridge.register(bridge: bridge), ["Google Chrome", "Brave"])
        let file = root.appendingPathComponent("Google/Chrome/NativeMessagingHosts/com.akinti.bridge.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "com.akinti.bridge")
        XCTAssertEqual(json["path"] as? String, bridge.path)
        XCTAssertEqual(json["type"] as? String, "stdio")
        XCTAssertEqual(json["allowed_origins"] as? [String], ["chrome-extension://ojpoadglbpcggeknbppjmhmeajdeiklk/"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Microsoft Edge").path)) // kurulu olmayana yazılmaz
    }

    /// manifest.json'daki "key" alanından hesaplanan kimlik, köprünün izin verdiği kimlikle aynı olmalı.
    func testExtensionIDMatchesManifestKey() throws {
        let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Extension/chrome/manifest.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(json["key"] as? String)))
        var hasher = SHA256Hasher(); hasher.update(key)
        let id = String(hasher.hex.prefix(32).map { Character(UnicodeScalar(UInt8(ascii: "a") + UInt8($0.hexDigitValue!))) })
        XCTAssertEqual(id, BrowserBridge.extensionIDs.first)
    }

    func testInstalledExtensionIsSyncedOnUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("bundle"), target = root.appendingPathComponent("Akıntı Eklentisi")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try Data(#"{"version":"1.1.0"}"#.utf8).write(to: source.appendingPathComponent("manifest.json"))
        try Data("yeni".utf8).write(to: source.appendingPathComponent("lib/core.js"))
        // Kullanıcı eklentiyi hiç kurmadıysa (klasör yok) dokunulmaz.
        XCTAssertFalse(BrowserBridge.syncInstalledExtension(from: source, to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        // Eski sürüm kuruluysa güncellenir; eski dosyalar kalmaz.
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(#"{"version":"1.0.0"}"#.utf8).write(to: target.appendingPathComponent("manifest.json"))
        try Data("eski".utf8).write(to: target.appendingPathComponent("eski.js"))
        XCTAssertTrue(BrowserBridge.syncInstalledExtension(from: source, to: target))
        XCTAssertEqual(BrowserBridge.manifestVersion(target), "1.1.0")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("lib/core.js"), encoding: .utf8), "yeni")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("eski.js").path))
        // Aynı sürümse tekrar kopyalanmaz.
        XCTAssertFalse(BrowserBridge.syncInstalledExtension(from: source, to: target))
    }
}

import CryptoKit
private struct SHA256Hasher {
    private var inner = SHA256()
    mutating func update(_ data: Data) { inner.update(data: data) }
    var hex: String { inner.finalize().map { String(format: "%02x", $0) }.joined() }
}
