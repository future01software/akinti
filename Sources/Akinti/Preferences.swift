import Foundation

struct Preferences: Codable, Equatable {
    var destinationPath: String
    var simultaneousDownloads = 3
    var retryLimit = 3
    var appearance = "system"
    /// Uygulama öne geldiğinde panodaki indirme bağlantısını yakalayıp ekleme penceresini açar.
    var clipboardCapture = true
    /// "system", "tr" veya "en".
    var language = "system"
    /// Bir indirme için en fazla bağlantı sayısı (parçalı indirme).
    var connectionsPerDownload = 8
    /// Toplam hız sınırı, KB/sn. 0 = sınırsız.
    var speedLimitKB = 0
    /// İndirme başlayınca IDM tarzı ilerleme penceresi aç.
    var showProgressWindow = true
    /// Torrent bitince paylaşmaya (seed) devam et.
    var torrentSeeding = false
    /// Menü çubuğunda (üst bar) Akıntı simgesi.
    var showMenuBarIcon = true
    /// Ana pencere kapanınca Dock simgesini gizle; yalnızca menü çubuğunda çalış.
    var menuBarOnly = false
    /// Dock'tan "Çık" denince kapanma; menü çubuğunda çalışmaya devam et.
    var keepRunningOnDockQuit = true
    /// Akıntı'nın kurduğu yt-dlp'yi günde bir kez denetleyip güncelle.
    var autoUpdateTools = true

    init(destinationPath: String) { self.destinationPath = destinationPath }

    // Eski settings.json dosyalarında olmayan alanlar varsayılan değerleriyle okunur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destinationPath = try c.decode(String.self, forKey: .destinationPath)
        simultaneousDownloads = try c.decodeIfPresent(Int.self, forKey: .simultaneousDownloads) ?? 3
        retryLimit = try c.decodeIfPresent(Int.self, forKey: .retryLimit) ?? 3
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        clipboardCapture = try c.decodeIfPresent(Bool.self, forKey: .clipboardCapture) ?? true
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        connectionsPerDownload = try c.decodeIfPresent(Int.self, forKey: .connectionsPerDownload) ?? 8
        speedLimitKB = try c.decodeIfPresent(Int.self, forKey: .speedLimitKB) ?? 0
        showProgressWindow = try c.decodeIfPresent(Bool.self, forKey: .showProgressWindow) ?? true
        torrentSeeding = try c.decodeIfPresent(Bool.self, forKey: .torrentSeeding) ?? false
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        menuBarOnly = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly) ?? false
        keepRunningOnDockQuit = try c.decodeIfPresent(Bool.self, forKey: .keepRunningOnDockQuit) ?? true
        autoUpdateTools = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateTools) ?? true
    }

    static var standard: Preferences {
        Preferences(destinationPath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Akıntı").path)
    }

    mutating func normalize() {
        simultaneousDownloads = min(8, max(1, simultaneousDownloads))
        retryLimit = min(5, max(0, retryLimit))
        if !["system", "light", "dark"].contains(appearance) { appearance = "system" }
        if AppLanguage(rawValue: language) == nil { language = "system" }
        connectionsPerDownload = min(16, max(1, connectionsPerDownload))
        speedLimitKB = max(0, speedLimitKB)
        if !destinationPath.hasPrefix("/") { destinationPath = Self.standard.destinationPath }
    }
}
