import Foundation
import CryptoKit
import Security

/// Akıntı'nın kendisi indirip güncel tuttuğu yardımcı araçlar (Homebrew gerekmez).
enum ManagedTool: String, CaseIterable, Identifiable {
    case ytdlp = "yt-dlp"
    case ffmpeg

    var id: String { rawValue }
    var fileName: String { rawValue }
    var title: String { rawValue }
    var purpose: String {
        switch self {
        case .ytdlp: return t("YouTube ve video siteleri", "YouTube and video sites")
        case .ffmpeg: return t("Yüksek kalitede görüntü + ses birleştirme, MP3", "Merging high-quality video + audio, MP3")
        }
    }
}

/// İndirme kaynakları. Testlerde yerel dosyalarla değiştirilir.
struct ToolSources {
    /// yt-dlp'nin son sürüm bilgisi (etiket). Dosyalar bu etiketin sürüm sayfasından indirilir.
    var ytdlpLatestAPI = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    var ytdlpAsset: (String) -> URL = { URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\($0)/yt-dlp_macos")! }
    var ytdlpSums: (String) -> URL = { URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\($0)/SHA2-256SUMS")! }
    /// Martin Riedl'in Apple Silicon için statik, Developer ID ile imzalı ve Apple onaylı ffmpeg derlemesi.
    var ffmpegZip = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")!
    /// ffmpeg'in imza gereksinimi: yalnızca bu geliştiricinin (Team ID) Apple imzası kabul edilir.
    var ffmpegRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"KU3N25YGLU\""
}

@MainActor
final class ToolManager: ObservableObject {
    static let shared = ToolManager()

    /// ~/Library/Application Support/Akinti/Tools (testlerde değiştirilir).
    nonisolated(unsafe) static var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Akinti/Tools", isDirectory: true)
    var sources = ToolSources()

    @Published private(set) var installing: Set<ManagedTool> = []
    @Published private(set) var progress: [ManagedTool: Double] = [:]
    @Published var lastError: String?

    enum ToolError: LocalizedError {
        case checksumMissing, checksumMismatch, signatureInvalid, badArchive, network(String)
        var errorDescription: String? {
            switch self {
            case .checksumMissing: return t("Doğrulama bilgisi bulunamadı; dosya kurulmadı.", "No checksum found; the file was not installed.")
            case .checksumMismatch: return t("İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor); kurulmadı.", "The download failed verification (SHA-256 mismatch); not installed.")
            case .signatureInvalid: return t("İndirilen dosyanın imzası beklenen geliştiriciye ait değil; kurulmadı.", "The download is not signed by the expected developer; not installed.")
            case .badArchive: return t("İndirilen arşiv açılamadı.", "Could not open the downloaded archive.")
            case .network(let m): return t("İndirme başarısız: ", "Download failed: ") + m
            }
        }
    }

    // MARK: Durum

    nonisolated static func installedURL(_ tool: ManagedTool) -> URL? {
        let url = folder.appendingPathComponent(tool.fileName)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    nonisolated static func installedVersion(_ tool: ManagedTool) -> String? {
        (try? String(contentsOf: folder.appendingPathComponent(tool.fileName + ".version"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isInstalling(_ tool: ManagedTool) -> Bool { installing.contains(tool) }

    /// Eksik olanları kurar (ör. ekleme penceresindeki "Kur" düğmesi).
    func installMissing(_ tools: [ManagedTool]) async {
        for tool in tools where Self.installedURL(tool) == nil && VideoEngine.find(tool.fileName) == nil {
            await install(tool)
        }
    }

    /// Kurar veya günceller. Hata olursa `lastError` doldurulur ve false döner.
    @discardableResult
    func install(_ tool: ManagedTool) async -> Bool {
        guard !installing.contains(tool) else { return false }
        installing.insert(tool); progress[tool] = 0; lastError = nil
        defer { installing.remove(tool); progress[tool] = nil }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            switch tool {
            case .ytdlp: try await installYtDlp()
            case .ffmpeg: try await installFFmpeg()
            }
            return true
        } catch {
            lastError = "\(tool.title): " + error.localizedDescription
            return false
        }
    }

    /// Kurulu yt-dlp'yi günde en fazla bir kez kontrol eder; yeni sürüm varsa indirir.
    /// YouTube sık değiştiği için yt-dlp'nin güncel kalması gerekir.
    func updateYtDlpIfNeeded(force: Bool = false) async {
        guard Self.installedURL(.ytdlp) != nil else { return }
        let key = "akinti.ytdlp.lastCheck"
        if !force, let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 24 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: key)
        guard let latest = try? await latestYtDlpTag(), latest != Self.installedVersion(.ytdlp) else { return }
        await install(.ytdlp)
    }

    // MARK: yt-dlp

    private func latestYtDlpTag() async throws -> String {
        var request = URLRequest(url: sources.ytdlpLatestAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data = try await fetch(request)
        guard let tag = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String else {
            throw ToolError.network(t("sürüm bilgisi okunamadı", "could not read version info"))
        }
        return tag
    }

    private func installYtDlp() async throws {
        let tag = try await latestYtDlpTag()
        let sums = String(decoding: try await fetch(URLRequest(url: sources.ytdlpSums(tag))), as: UTF8.self)
        guard let expected = Self.checksum(for: "yt-dlp_macos", in: sums) else { throw ToolError.checksumMissing }
        let file = try await download(sources.ytdlpAsset(tag), tool: .ytdlp)
        defer { try? FileManager.default.removeItem(at: file) }
        guard try Self.sha256(of: file) == expected else { throw ToolError.checksumMismatch }
        try place(file, as: .ytdlp, version: tag)
    }

    /// SHA2-256SUMS biçimi: "<özet>  <dosya adı>" satırları.
    nonisolated static func checksum(for name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts.last.map(String.init) == name, parts[0].count == 64 { return parts[0].lowercased() }
        }
        return nil
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: ffmpeg

    private func installFFmpeg() async throws {
        let (zip, finalURL) = try await downloadReturningURL(sources.ffmpegZip, tool: .ffmpeg)
        defer { try? FileManager.default.removeItem(at: zip) }
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent("akinti-ffmpeg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run(); ditto.waitUntilExit()
        let binary = unpacked.appendingPathComponent("ffmpeg")
        guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: binary.path) else { throw ToolError.badArchive }
        guard Self.isSigned(binary, requirement: sources.ffmpegRequirement) else { throw ToolError.signatureInvalid }
        // Sürüm, yönlendirilen adresten okunur: .../1789931890_9.0.2/ffmpeg.zip -> 9.0.2
        let folder = finalURL.deletingLastPathComponent().lastPathComponent
        try place(binary, as: .ffmpeg, version: folder.split(separator: "_").last.map(String.init) ?? folder)
    }

    /// Kod imzası geçerli ve verilen gereksinimi (ör. belirli bir geliştirici) karşılıyor mu?
    nonisolated static func isSigned(_ file: URL, requirement: String) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req) == errSecSuccess
    }

    // MARK: İndirme ve yerleştirme

    private func fetch(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw ToolError.network("HTTP \(http.statusCode)") }
            return data
        } catch let error as ToolError { throw error } catch { throw ToolError.network(error.localizedDescription) }
    }

    private func download(_ url: URL, tool: ManagedTool) async throws -> URL { try await downloadReturningURL(url, tool: tool).0 }

    /// İlerlemeyi `progress` üzerinden bildirir; yönlendirmeden sonraki son adresi de döndürür.
    private func downloadReturningURL(_ url: URL, tool: ManagedTool) async throws -> (URL, URL) {
        try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                observation?.invalidate()
                if let error { return continuation.resume(throwing: ToolError.network(error.localizedDescription)) }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return continuation.resume(throwing: ToolError.network("HTTP \(http.statusCode)"))
                }
                guard let location else { return continuation.resume(throwing: ToolError.network("?")) }
                // Geçici dosya bu blok bitince silinir; hemen taşınır.
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("akinti-\(tool.fileName)-\(UUID().uuidString)")
                do {
                    try FileManager.default.moveItem(at: location, to: out)
                    continuation.resume(returning: (out, response?.url ?? url))
                } catch { continuation.resume(throwing: ToolError.network(error.localizedDescription)) }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let fraction = p.fractionCompleted
                Task { @MainActor in if self?.installing.contains(tool) == true { self?.progress[tool] = fraction } }
            }
            task.resume()
        }
    }

    /// Doğrulanmış dosyayı araç klasörüne atomik olarak yerleştirir ve çalıştırılabilir yapar.
    private func place(_ file: URL, as tool: ManagedTool, version: String) throws {
        let target = Self.folder.appendingPathComponent(tool.fileName)
        let staging = Self.folder.appendingPathComponent(tool.fileName + ".new")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.copyItem(at: file, to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
        try version.write(to: Self.folder.appendingPathComponent(tool.fileName + ".version"), atomically: true, encoding: .utf8)
    }
}
