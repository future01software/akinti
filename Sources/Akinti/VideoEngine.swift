import Foundation

/// Video sitesi bağlantıları için kalite seçenekleri (yt-dlp biçim seçicilerine çevrilir).
enum VideoQuality: String, CaseIterable, Identifiable {
    case best, p2160, p1080, p720, p480, audioM4A, audioMP3

    var id: String { rawValue }
    var isAudio: Bool { self == .audioM4A || self == .audioMP3 }
    var height: Int? {
        switch self {
        case .p2160: return 2160
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .best: return t("En iyi kalite", "Best quality")
        case .p2160: return "4K (2160p)"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .audioM4A: return t("Yalnızca ses (M4A)", "Audio only (M4A)")
        case .audioMP3: return t("Yalnızca ses (MP3)", "Audio only (MP3)")
        }
    }

    /// ffmpeg yoksa ayrı görüntü+ses akışları birleştirilemez; tek dosyalık en iyi biçim seçilir.
    func arguments(hasFFmpeg: Bool) -> [String] {
        switch self {
        case .audioM4A:
            return ["-f", "ba[ext=m4a]/ba/b"]
        case .audioMP3:
            return hasFFmpeg ? ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"] : ["-f", "ba[ext=m4a]/ba/b"]
        default:
            let h = height.map { "[height<=\($0)]" } ?? ""
            // Aynı çözünürlükte H.264 + AAC tercih edilir: QuickTime ve tüm Mac'lerde sorunsuz oynar.
            // (4K gibi yalnızca VP9/AV1 olan çözünürlüklerde mecburen o codec indirilir.)
            let sort = ["-S", "res,vcodec:h264,acodec:m4a"]
            return hasFFmpeg ? ["-f", "bv*\(h)+ba/b\(h)/b", "--merge-output-format", "mp4"] + sort : ["-f", "b\(h)/b"] + sort
        }
    }
}

/// Bağlantının nasıl indirileceği: otomatik algıla, doğrudan dosya ya da video sayfası.
enum LinkMode: String, CaseIterable, Identifiable {
    case auto, file, video
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return t("Otomatik", "Automatic")
        case .file: return t("Dosya", "File")
        case .video: return t("Video sayfası", "Video page")
        }
    }
    func treatsAsVideo(_ url: URL) -> Bool {
        switch self {
        case .auto: return VideoEngine.isVideoPage(url)
        case .file: return false
        case .video: return true
        }
    }
}

struct PlaylistEntry: Hashable {
    var url: URL
    var title: String
}

struct VideoInfo {
    var title: String
    var duration: Double?
    var thumbnail: URL?
    var site: String
    var maxHeight: Int?
    /// Bağlantı bir oynatma listesiyse içindeki videolar.
    var entries: [PlaylistEntry] = []
    var isPlaylist: Bool { !entries.isEmpty }
}

enum VideoEngine {
    /// Otomatik olarak video sayfası sayılan siteler (yt-dlp bunlardan çok daha fazlasını destekler).
    static let videoHosts = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv", "x.com", "twitter.com",
                             "instagram.com", "tiktok.com", "facebook.com", "fb.watch", "reddit.com", "soundcloud.com",
                             "bilibili.com", "streamable.com", "rumble.com", "ted.com", "bandcamp.com", "mixcloud.com"]

    static func isVideoPage(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        // Siteden doğrudan bir dosya (ör. .zip) isteniyorsa normal indirme kullanılır.
        if ![.other, .video, .music].contains(FileCategory.of(url.lastPathComponent)) { return false }
        return videoHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Testlerde sahte bir yt-dlp betiği vermek için.
    static var overrideExecutable: URL?
    static var executable: URL? { overrideExecutable ?? find("yt-dlp") }
    static var ffmpeg: URL? { overrideExecutable == nil ? find("ffmpeg") : nil }
    static let installCommand = "brew install yt-dlp ffmpeg"

    private static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fromEnv = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/opt/local/bin"] + fromEnv
    }

    static func find(_ name: String) -> URL? {
        for dir in searchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Uygulamalar Finder'dan açıldığında PATH kısadır; yt-dlp'nin yardımcı araçları bulabilmesi için genişletilir.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin"] + (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    enum EngineError: LocalizedError {
        case missing, failed(String)
        var errorDescription: String? {
            switch self {
            case .missing: return t("yt-dlp kurulu değil. Terminal’de şunu çalıştırın: ", "yt-dlp is not installed. Run this in Terminal: ") + VideoEngine.installCommand
            case .failed(let message): return message
            }
        }
    }

    /// Sayfa bilgisini (başlık, süre, küçük resim) indirmeden alır.
    /// Oynatma listesi parametresi olan bağlantılar (YouTube list=, SoundCloud sets, Bandcamp album…).
    static func isPlaylist(_ url: URL) -> Bool {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let path = url.path.lowercased()
        return query.contains { $0.name == "list" && !($0.value ?? "").isEmpty }
            || path.hasPrefix("/playlist") || path.contains("/sets/") || path.contains("/album/") || path.contains("/showcase/")
    }
    /// Listede belirli bir video da seçili mi (ör. watch?v=…&list=…)? Değilse bağlantı yalnızca listedir.
    static func hasSingleVideo(_ url: URL) -> Bool {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return query.contains { $0.name == "v" } || url.host?.hasSuffix("youtu.be") == true
    }

    static func probe(_ url: URL) async throws -> VideoInfo {
        guard let exe = executable else { throw EngineError.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = exe
                // --flat-playlist: listelerde her videoyu tek tek çözmeden yalnızca başlık ve bağlantıları alır (hızlı).
                process.arguments = ["-J", "--flat-playlist", "--no-warnings"] + (isPlaylist(url) ? [] : ["--no-playlist"]) + ["--", url.absoluteString]
                process.environment = environment
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                var errData = Data()
                let errLock = NSLock()
                err.fileHandleForReading.readabilityHandler = { h in
                    let d = h.availableData
                    if d.isEmpty { h.readabilityHandler = nil; return } // EOF: aksi halde boş veriyle sürekli çağrılır
                    errLock.lock(); errData.append(d); errLock.unlock()
                }
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                err.fileHandleForReading.readabilityHandler = nil
                guard process.terminationStatus == 0,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    errLock.lock(); let text = String(decoding: errData, as: UTF8.self); errLock.unlock()
                    continuation.resume(throwing: EngineError.failed(lastError(in: text) ?? t("Bu sayfada video bulunamadı.", "No video found on this page.")))
                    return
                }
                let heights = (json["formats"] as? [[String: Any]] ?? []).compactMap { $0["height"] as? Int }
                let entries: [PlaylistEntry] = (json["entries"] as? [[String: Any]] ?? []).compactMap { e in
                    let link = [e["url"], e["webpage_url"], e["original_url"]].compactMap { $0 as? String }.first { $0.hasPrefix("http") }
                    guard let link, let entryURL = URL(string: link) else { return nil }
                    return PlaylistEntry(url: entryURL, title: e["title"] as? String ?? link)
                }
                let thumbs = json["thumbnails"] as? [[String: Any]]
                continuation.resume(returning: VideoInfo(
                    title: json["title"] as? String ?? url.absoluteString,
                    duration: json["duration"] as? Double ?? (json["duration"] as? Int).map(Double.init),
                    thumbnail: ((json["thumbnail"] as? String) ?? (thumbs?.last?["url"] as? String)).flatMap(URL.init(string:)),
                    site: json["extractor_key"] as? String ?? url.host ?? "",
                    maxHeight: heights.max(),
                    entries: entries))
            }
        }
    }

    static func lastError(in text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let line = lines.last(where: { $0.hasPrefix("ERROR:") }) ?? lines.last, !line.isEmpty else { return nil }
        return line.replacingOccurrences(of: "ERROR: ", with: "")
    }
}

/// Tek bir video indirmesi: yt-dlp'yi çalıştırır, ilerlemeyi okur. Duraklatma = süreci durdurmak;
/// yeniden başlatınca yt-dlp yarım kalan .part dosyasından devam eder.
final class VideoJob {
    var onProgress: ((Int64, Int64) -> Void)?
    var onFinish: ((URL?, Int32, String) -> Void)?
    private(set) var userCancelled = false
    private let process = Process()
    private var outBuffer = ""
    private var errText = ""
    private var savedFile: URL?

    init(executable: URL, url: URL, folder: URL, quality: VideoQuality, ffmpeg: URL?, rateLimit: Int64? = nil, fragments: Int = 1) {
        process.executableURL = executable
        var args = ["--newline", "--no-playlist", "--no-mtime", "--progress", "--quiet", "--no-warnings",
                    "--progress-template", "download:AKINTI %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
                    "--print", "after_move:AKINTIFILE %(filepath)s",
                    "-P", folder.path, "-o", "%(title).150B [%(id)s].%(ext)s"]
        if let ffmpeg { args += ["--ffmpeg-location", ffmpeg.path] }
        if let rateLimit { args += ["--limit-rate", String(rateLimit)] }
        if fragments > 1 { args += ["--concurrent-fragments", String(fragments)] }
        args += quality.arguments(hasFFmpeg: ffmpeg != nil)
        args += ["--", url.absoluteString] // "--": bağlantı asla seçenek olarak yorumlanmasın
        process.arguments = args
        process.environment = VideoEngine.environment
    }

    func start() throws {
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return } // EOF
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return } // EOF
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.errText = String(((self?.errText ?? "") + text).suffix(4000)) }
        }
        process.terminationHandler = { [weak self] p in
            // Kalan çıktının okunması için kısa bir gecikme.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                guard let self else { return }
                self.consume("\n")
                self.onFinish?(self.savedFile, p.terminationStatus, VideoEngine.lastError(in: self.errText) ?? "")
            }
        }
        try process.run()
    }

    func cancel() {
        userCancelled = true
        if process.isRunning { process.interrupt() }
    }

    /// Uygulama kapanırken: kibarca durdur, 2 sn içinde kapanmazsa zorla sonlandır.
    func terminateAndWait() {
        cancel()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate() }
    }

    private func consume(_ text: String) {
        outBuffer += text
        while let range = outBuffer.range(of: "\n") {
            let line = String(outBuffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            outBuffer.removeSubrange(..<range.upperBound)
            if line.hasPrefix("AKINTIFILE ") {
                savedFile = URL(fileURLWithPath: String(line.dropFirst("AKINTIFILE ".count)))
            } else if line.hasPrefix("AKINTI ") {
                let parts = line.split(separator: " ").dropFirst().map { Double($0) }
                guard parts.count >= 3, let received = parts[0] else { continue }
                let total = parts[1] ?? parts[2] ?? 0
                onProgress?(Int64(received), Int64(total))
            }
        }
    }
}
