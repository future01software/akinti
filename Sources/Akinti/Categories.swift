import SwiftUI

/// IDM benzeri dosya kategorileri; dosya uzantısından otomatik belirlenir.
enum FileCategory: String, CaseIterable, Identifiable, Hashable {
    case compressed = "Arşivler"
    case documents = "Belgeler"
    case music = "Müzik"
    case video = "Videolar"
    case images = "Görseller"
    case programs = "Programlar"
    case other = "Diğer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compressed: return t("Arşivler", "Archives")
        case .documents: return t("Belgeler", "Documents")
        case .music: return t("Müzik", "Music")
        case .video: return t("Videolar", "Videos")
        case .images: return t("Görseller", "Images")
        case .programs: return t("Programlar", "Programs")
        case .other: return t("Diğer", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .compressed: return "doc.zipper"
        case .documents: return "doc.richtext"
        case .music: return "music.note"
        case .video: return "film"
        case .images: return "photo"
        case .programs: return "app.badge"
        case .other: return "doc"
        }
    }

    var tint: Color {
        switch self {
        case .compressed: return .orange
        case .documents: return .blue
        case .music: return .pink
        case .video: return .purple
        case .images: return .teal
        case .programs: return .green
        case .other: return .gray
        }
    }

    private static let extensions: [FileCategory: Set<String>] = [
        .compressed: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz", "lzma", "cab", "iso", "sit", "sitx"],
        .documents: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md", "csv", "epub", "odt", "ods", "odp", "json", "xml"],
        .music: ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "opus", "wma", "alac"],
        .video: ["mp4", "m4v", "mov", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "m3u8"],
        .images: ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg", "raw", "psd", "ico"],
        .programs: ["dmg", "pkg", "app", "exe", "msi", "deb", "rpm", "appimage", "apk", "ipa", "jar", "bin", "sh"],
    ]

    static func of(_ fileName: String) -> FileCategory {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }
        return extensions.first { $0.value.contains(ext) }?.key ?? .other
    }
}

/// Kenar çubuğundaki durum grupları.
enum StatusFilter: String, CaseIterable, Identifiable, Hashable {
    case active = "İndiriliyor"
    case unfinished = "Tamamlanmamış"
    case queued = "Kuyrukta"
    case finished = "Tamamlandı"
    case failed = "Hatalı"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return t("İndiriliyor", "Downloading")
        case .unfinished: return t("Tamamlanmamış", "Unfinished")
        case .queued: return t("Kuyrukta", "Queued")
        case .finished: return t("Tamamlandı", "Finished")
        case .failed: return t("Hatalı", "Failed")
        }
    }

    var symbol: String {
        switch self {
        case .active: return "arrow.down.circle"
        case .unfinished: return "circle.dashed"
        case .queued: return "clock"
        case .finished: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    func matches(_ d: Download) -> Bool {
        switch self {
        case .active: return ["İndiriliyor", "Duraklatılıyor"].contains(d.state)
        case .unfinished: return d.state != "Tamamlandı"
        case .queued: return ["Bekliyor", "Planlandı", "Yeniden denenecek"].contains(d.state)
        case .finished: return d.state == "Tamamlandı"
        case .failed: return d.state == "Hata"
        }
    }
}

enum SidebarSelection: Hashable {
    case all
    case category(FileCategory)
    case status(StatusFilter)

    var title: String {
        switch self {
        case .all: return t("Tüm indirmeler", "All Downloads")
        case .category(let c): return c.title
        case .status(let s): return s.title
        }
    }

    func matches(_ d: Download) -> Bool {
        switch self {
        case .all: return true
        case .category(let c): return d.category == c
        case .status(let s): return s.matches(d)
        }
    }
}

/// Hız sınırı seçenekleri (KB/sn); 0 = sınırsız.
enum SpeedLimit {
    static let options = [0, 256, 512, 1024, 2048, 5120, 10240, 25600]
    static func title(_ kb: Int) -> String {
        if kb == 0 { return t("Sınırsız", "Unlimited") }
        return (kb >= 1024 ? "\(kb / 1024) MB" : "\(kb) KB") + t("/sn", "/s")
    }
}

enum Format {
    /// Türkçede "%34", İngilizcede "34%".
    static func percent(_ fraction: Double) -> String { let n = Int(fraction * 100); return t("%\(n)", "\(n)%") }
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false // "Zero KB" yerine "0 KB"
        return f
    }()
    static func bytes(_ value: Int64) -> String { byteFormatter.string(fromByteCount: value) }
    static func speed(_ bytesPerSecond: Double) -> String { (bytesPerSecond < 1 ? "0 KB" : bytes(Int64(bytesPerSecond))) + t("/sn", "/s") }
    static func eta(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let (sec, min, hr) = (t("sn", "s"), t("dk", "min"), t("sa", "h"))
        if seconds < 1 { return "< 1 \(sec)" }
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) \(sec)" }
        if s < 3600 { return "\(s / 60) \(min) \(s % 60) \(sec)" }
        return "\(s / 3600) \(hr) \((s % 3600) / 60) \(min)"
    }
}
