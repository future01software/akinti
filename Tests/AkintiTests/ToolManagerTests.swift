import XCTest
@testable import Akinti

/// Bileşen kurulumu: SHA-256 ve imza doğrulaması, atomik yerleştirme. Ağ yerine file:// kaynaklar kullanılır.
@MainActor
final class ToolManagerTests: XCTestCase {
    private var root: URL!
    private var originalFolder: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        originalFolder = ToolManager.folder
        ToolManager.folder = root.appendingPathComponent("Tools")
    }

    override func tearDown() async throws {
        ToolManager.folder = originalFolder
        try? FileManager.default.removeItem(at: root)
    }

    /// Sahte yt-dlp sürümü: latest.json + ikili + SHA2-256SUMS.
    private func fakeRelease(tag: String, binary: Data, sumsHash: String? = nil) throws -> ToolSources {
        let dir = root.appendingPathComponent("release-\(tag)"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"tag_name":"\#(tag)"}"#.utf8).write(to: dir.appendingPathComponent("latest.json"))
        let bin = dir.appendingPathComponent("yt-dlp_macos"); try binary.write(to: bin)
        let hash = try sumsHash ?? ToolManager.sha256(of: bin)
        try Data("\(hash)  yt-dlp_macos\nffff  yt-dlp.exe\n".utf8).write(to: dir.appendingPathComponent("SHA2-256SUMS"))
        var sources = ToolSources()
        sources.ytdlpLatestAPI = dir.appendingPathComponent("latest.json")
        sources.ytdlpAsset = { _ in bin }
        sources.ytdlpSums = { _ in dir.appendingPathComponent("SHA2-256SUMS") }
        return sources
    }

    func testChecksumParsing() {
        let sums = "0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa  yt-dlp_macos\nabc  yt-dlp_macos.zip\n"
        XCTAssertEqual(ToolManager.checksum(for: "yt-dlp_macos", in: sums), "0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa")
        XCTAssertNil(ToolManager.checksum(for: "yt-dlp_macos.zip", in: sums)) // 64 karakter değil
        XCTAssertNil(ToolManager.checksum(for: "yok", in: sums))
    }

    func testInstallsVerifiedYtDlpAndUpdates() async throws {
        let manager = ToolManager()
        manager.sources = try fakeRelease(tag: "2026.01.01", binary: Data("#!/bin/sh\necho v1\n".utf8))
        let ok = await manager.install(.ytdlp)
        XCTAssertTrue(ok, manager.lastError ?? "")
        let installed = try XCTUnwrap(ToolManager.installedURL(.ytdlp))
        XCTAssertEqual(ToolManager.installedVersion(.ytdlp), "2026.01.01")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.path))
        XCTAssertEqual(VideoEngine.find("yt-dlp"), installed) // Akıntı'nın kurduğu, Homebrew'dan önce gelir

        // Yeni sürüm: zorla denetle -> güncellenir
        manager.sources = try fakeRelease(tag: "2026.02.02", binary: Data("#!/bin/sh\necho v2\n".utf8))
        await manager.updateYtDlpIfNeeded(force: true)
        XCTAssertEqual(ToolManager.installedVersion(.ytdlp), "2026.02.02")
        XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8), "#!/bin/sh\necho v2\n")
    }

    func testRejectsChecksumMismatch() async throws {
        let manager = ToolManager()
        manager.sources = try fakeRelease(tag: "2026.03.03", binary: Data("kötü".utf8), sumsHash: String(repeating: "0", count: 64))
        let ok = await manager.install(.ytdlp)
        XCTAssertFalse(ok)
        XCTAssertNil(ToolManager.installedURL(.ytdlp), "doğrulanmayan dosya kurulmamalı")
        XCTAssertTrue(manager.lastError?.contains("SHA-256") == true)
    }

    func testSignatureRequirement() {
        let ls = URL(fileURLWithPath: "/bin/ls")
        XCTAssertTrue(ToolManager.isSigned(ls, requirement: "anchor apple"))                 // Apple imzalı
        XCTAssertFalse(ToolManager.isSigned(ls, requirement: ToolSources().ffmpegRequirement)) // ffmpeg geliştiricisi değil
        let unsigned = root.appendingPathComponent("unsigned"); try? Data("x".utf8).write(to: unsigned)
        XCTAssertFalse(ToolManager.isSigned(unsigned, requirement: "anchor apple"))
    }

    func testRejectsFFmpegWithWrongSignature() async throws {
        // /bin/ls'yi "ffmpeg" adıyla zip'le: arşiv geçerli ama imza ffmpeg geliştiricisine ait değil
        let stage = root.appendingPathComponent("stage"); try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: stage.appendingPathComponent("ffmpeg"))
        let zip = root.appendingPathComponent("ffmpeg.zip")
        let ditto = Process(); ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", stage.appendingPathComponent("ffmpeg").path, zip.path]
        try ditto.run(); ditto.waitUntilExit()
        let manager = ToolManager()
        manager.sources.ffmpegZip = zip
        let ok = await manager.install(.ffmpeg)
        XCTAssertFalse(ok)
        XCTAssertNil(ToolManager.installedURL(.ffmpeg))
        XCTAssertTrue(manager.lastError?.contains(t("imza", "signed")) == true, manager.lastError ?? "")
    }
}
