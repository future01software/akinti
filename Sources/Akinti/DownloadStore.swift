import Foundation
import Combine

struct Download: Identifiable, Codable {
    var id = UUID()
    var source: URL
    var name: String
    var state = "Bekliyor"
    var received: Int64 = 0
    var total: Int64 = 0
    var saved: URL?
    var error: String?
    var scheduledAt: Date?
    var retryCount: Int?
    var retryAt: Date?
    var destinationFolder: URL?
    var addedAt: Date?
    var completedAt: Date?
    /// Video sitesi bağlantısı mı (yt-dlp ile indirilir)?
    var isVideo: Bool?
    var videoQuality: String?
    /// Çok bağlantılı indirmede her bağlantının bayt aralığı ve ilerlemesi (devam için saklanır).
    var segments: [Segment]?
    /// Torrent / magnet indirmesi mi (aria2 ile)?
    var isTorrent: Bool?
    /// Yerel .torrent dosyasının içeriği (bağlantı yerine dosyadan eklendiyse).
    var torrentFile: Data?
    var seeders: Int?
    var peers: Int?
    /// Torrent parça haritası: dosya eşit bölmelere ayrılır, her bölmenin inmiş parça oranı (0…1).
    var pieceMap: [Double]?

    var category: FileCategory {
        if isTorrent == true { return .torrents }
        let byName = FileCategory.of(name)
        guard isVideo == true, byName == .other else { return byName }
        return VideoQuality(rawValue: videoQuality ?? "")?.isAudio == true ? .music : .video
    }
    var addedDate: Date { addedAt ?? .distantPast }
    var progress: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    var canStart: Bool { ["Duraklatıldı", "Hata", "Planlandı", "Yeniden denenecek"].contains(state) }
    var canPause: Bool { ["İndiriliyor", "Bekliyor", "Planlandı", "Yeniden denenecek"].contains(state) }
}

final class DownloadStore: ObservableObject {
    @Published var items: [Download] = []
    @Published var message: String?
    /// Saniyelik ortalama indirme hızı (bayt/sn); yalnızca aktif indirmeler için.
    @Published private(set) var speeds: [UUID: Double] = [:]
    /// Bağlantı ekleme penceresini menüden/klavye kısayolundan açmak için.
    @Published var isAdding = false
    @Published var isShowingHelp = false
    @Published var pendingLinks = ""
    /// Açılması istenen indirme pencereleri (arayüz okuyup boşaltır).
    @Published var popupRequests: [UUID] = []
    /// Bir seferde bundan fazla indirme eklenirse (ör. oynatma listesi) pencere açılmaz.
    static let maxPopupsPerAdd = 3
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return } // aynı değer: kaydetme, yeniden başlatma yok
            L10n.preference = preferences.language
            if preferences.menuBarOnly != oldValue.menuBarOnly || preferences.showMenuBarIcon != oldValue.showMenuBarIcon {
                NotificationCenter.default.post(name: DownloadStore.dockPolicyChanged, object: nil)
            }
            limiter.bytesPerSecond = Double(preferences.speedLimitKB) * 1024
            savePreferences()
            if preferences.simultaneousDownloads > oldValue.simultaneousDownloads { pump() }
            if torrentEngine.isRunning, preferences.speedLimitKB != oldValue.speedLimitKB || preferences.torrentSeeding != oldValue.torrentSeeding {
                Task { @MainActor in try? await self.torrentEngine.start(seeding: self.preferences.torrentSeeding, speedLimit: Int64(self.preferences.speedLimitKB) * 1024) }
            }
        }
    }

    static let dockPolicyChanged = Notification.Name("AkintiDockPolicyChanged")
    let limiter = RateLimiter()
    private var httpJobs: [UUID: HTTPJob] = [:]
    private var videoJobs: [UUID: VideoJob] = [:]
    /// Torrent indirmeleri: indirme kimliği -> aria2 GID.
    private var torrentJobs: [UUID: String] = [:]
    private var torrentStarting: Set<UUID> = []
    private var pollingTorrents = false
    lazy var torrentEngine = TorrentEngine()
    private var running: Int { httpJobs.count + videoJobs.count + torrentJobs.count + torrentStarting.count }
    private var lastSample: [UUID: Int64] = [:]
    private var ticker: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?
    private let storage: URL
    private let preferencesFile: URL
    private let partialFolder: URL

    var totalSpeed: Double { speeds.values.reduce(0, +) }
    var limit: Int {
        get { preferences.simultaneousDownloads }
        set { preferences.simultaneousDownloads = min(8, max(1, newValue)) }
    }
    var destinationFolder: URL { URL(fileURLWithPath: preferences.destinationPath, isDirectory: true) }
    func eta(for d: Download) -> Double? {
        guard d.state == "İndiriliyor", d.total > 0, let s = speeds[d.id], s > 1 else { return nil }
        return Double(d.total - d.received) / s
    }

    init(directory: URL? = nil, destination: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Akinti")
        preferencesFile = dir.appendingPathComponent("settings.json")
        storage = dir.appendingPathComponent("downloads.json")
        partialFolder = dir.appendingPathComponent("partial", isDirectory: true)
        var initialPreferences = (try? Data(contentsOf: preferencesFile)).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? .standard
        if let destination { initialPreferences.destinationPath = destination.path }
        initialPreferences.normalize()
        preferences = initialPreferences
        L10n.preference = initialPreferences.language
        limiter.bytesPerSecond = Double(initialPreferences.speedLimitKB) * 1024
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: storage), let loaded = try? JSONDecoder().decode([Download].self, from: data) {
            items = loaded.map {
                var d = $0
                if d.destinationFolder == nil { d.destinationFolder = destinationFolder }
                if d.state == "İndiriliyor" || d.state == "Duraklatılıyor" { d.state = "Duraklatıldı" }
                return d
            }
        }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        // Uygulama kapanırken yt-dlp süreçleri durdurulur ve parçaların ilerlemesi kaydedilir.
        terminationObserver = NotificationCenter.default.addObserver(forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.prepareForQuit()
        }
    }

    // MARK: Ayarlar ve kayıt

    private func savePreferences() {
        do { try JSONEncoder().encode(preferences).write(to: preferencesFile, options: .atomic) }
        catch { message = t("Ayarlar kaydedilemedi: ", "Could not save settings: ") + error.localizedDescription }
    }
    func chooseDestination(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard folder.isFileURL, FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue, FileManager.default.isWritableFile(atPath: folder.path) else {
            message = t("Yazılabilir bir klasör seçin.", "Choose a writable folder."); return false
        }
        preferences.destinationPath = folder.path
        return true
    }
    func persist() {
        do { try JSONEncoder().encode(items).write(to: storage, options: .atomic) }
        catch { message = t("Geçmiş kaydedilemedi: ", "Could not save history: ") + error.localizedDescription }
    }
    private func partURL(_ id: UUID) -> URL { partialFolder.appendingPathComponent("\(id.uuidString).part") }

    // MARK: Zamanlayıcı ve hız

    func tick() {
        let now = Date()
        var changed = false
        for i in items.indices {
            if (items[i].state == "Planlandı" && (items[i].scheduledAt ?? .distantFuture) <= now) || (items[i].state == "Yeniden denenecek" && (items[i].retryAt ?? .distantFuture) <= now) {
                items[i].state = "Bekliyor"; changed = true
            }
        }
        if changed { pump() }
        pollTorrents()
        sampleSpeeds()
        // Aktif indirmelerin parça ilerlemesi 5 sn'de bir kaydedilir; uygulama aniden kapanırsa en fazla birkaç saniyelik veri yeniden iner.
        tickCount += 1
        if tickCount % 5 == 0, running > 0 { persist() }
    }
    private var tickCount = 0
    private func sampleSpeeds() {
        var next: [UUID: Double] = [:]
        for d in items where d.state == "İndiriliyor" {
            let delta = Double(max(0, d.received - (lastSample[d.id] ?? d.received)))
            next[d.id] = speeds[d.id].map { $0 * 0.4 + delta * 0.6 } ?? delta
            lastSample[d.id] = d.received
        }
        lastSample = lastSample.filter { next[$0.key] != nil }
        if next != speeds { speeds = next }
    }

    // MARK: Ekleme ve kuyruk

    /// Metindeki geçerli HTTP/HTTPS bağlantılarını ayıklar (pano ve sürükle-bırak için).
    static func links(in text: String) -> [URL] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .compactMap { URL(string: $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()[],;"))) }
            .filter { (["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil) || TorrentEngine.isMagnet($0) }
    }
    func add(_ text: String, scheduledAt: Date? = nil, startPaused: Bool = false,
             mode: LinkMode = .auto, quality: VideoQuality = .best, titles: [URL: String] = [:]) -> Bool {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let urls = lines.compactMap { URL(string: $0) }.filter { (["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil) || TorrentEngine.isMagnet($0) }
        guard !lines.isEmpty, urls.count == lines.count else { message = t("Her satıra geçerli bir HTTP, HTTPS veya magnet bağlantısı yazın.", "Enter one valid HTTP, HTTPS or magnet link per line."); return false }
        for url in urls {
            var item = Download(source: url, name: url.lastPathComponent.isEmpty ? t("İndirme", "Download") : url.lastPathComponent)
            if TorrentEngine.isMagnet(url) || (mode != .file && TorrentEngine.isTorrentLink(url)) {
                item.isTorrent = true
                item.name = titles[url] ?? TorrentEngine.displayName(url)
            } else if mode.treatsAsVideo(url) {
                item.isVideo = true
                item.videoQuality = quality.rawValue
                item.name = titles[url] ?? "\(url.host ?? "Video") – \(quality.title)"
            }
            item.destinationFolder = destinationFolder
            item.addedAt = Date()
            if let date = scheduledAt, date > Date() { item.scheduledAt = date; item.state = "Planlandı" }
            else if startPaused { item.state = "Duraklatıldı" }
            items.append(item)
            if preferences.showProgressWindow, item.state == "Bekliyor", urls.count <= Self.maxPopupsPerAdd { popupRequests.append(item.id) }
        }
        persist(); pump(); return true
    }
    /// Yerel bir .torrent dosyasını ekler (sürükle-bırak, Dosya > Torrent aç, Finder'dan açma).
    @discardableResult
    func addTorrentFile(_ file: URL, startPaused: Bool = false) -> Bool {
        guard let data = try? Data(contentsOf: file), data.first == UInt8(ascii: "d") else {
            message = t("Geçerli bir .torrent dosyası seçin.", "Choose a valid .torrent file."); return false
        }
        var item = Download(source: file, name: file.deletingPathExtension().lastPathComponent)
        item.isTorrent = true
        item.torrentFile = data
        item.destinationFolder = destinationFolder
        item.addedAt = Date()
        if startPaused { item.state = "Duraklatıldı" }
        items.append(item)
        if preferences.showProgressWindow, !startPaused { popupRequests.append(item.id) }
        persist(); pump(); return true
    }
    func pump() {
        for item in items where item.state == "Bekliyor" {
            guard running < limit else { break }
            if item.isTorrent == true { startTorrent(item.id) }
            else if item.isVideo == true { startVideo(item.id) }
            else { startHTTP(item.id) }
        }
        persist()
    }
    func pause(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if let job = httpJobs[id] {
            // Bağlantılar kapanana kadar "Duraklatılıyor"; ilerleme parçalarda korunur.
            items[i].state = "Duraklatılıyor"; job.cancel(); return
        }
        if let gid = torrentJobs.removeValue(forKey: id) {
            // aria2'den çıkarılır; dosyalar ve .aria2 devam bilgisi kalır. Kaldırma bitene kadar "Duraklatılıyor".
            items[i].state = "Duraklatılıyor"
            Task { @MainActor in
                await self.torrentEngine.remove(gid)
                if let i = self.items.firstIndex(where: { $0.id == id }), self.items[i].state == "Duraklatılıyor" { self.items[i].state = "Duraklatıldı" }
                self.persist(); self.pump()
            }
            return
        }
        if torrentStarting.contains(id) { items[i].state = "Duraklatıldı"; persist(); return }
        if let job = videoJobs[id] {
            // Süreç gerçekten kapanana kadar "Duraklatılıyor": aynı dosyaya ikinci yt-dlp başlatılamaz.
            items[i].state = "Duraklatılıyor"; job.cancel(); persist(); return
        }
        if ["Bekliyor", "Planlandı", "Yeniden denenecek"].contains(items[i].state) { items[i].state = "Duraklatıldı"; persist() }
    }
    func start(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), httpJobs[id] == nil, videoJobs[id] == nil, torrentJobs[id] == nil, !torrentStarting.contains(id), items[i].canStart else { return }
        items[i].state = "Bekliyor"; items[i].retryCount = 0; items[i].retryAt = nil; items[i].scheduledAt = nil; pump()
    }
    /// Listeden kaldırır. `trashFile` true ise indirilen dosya Çöp Sepeti'ne taşınır (geri alınabilir).
    func remove(_ id: UUID, trashFile: Bool = false) {
        if let job = httpJobs.removeValue(forKey: id) { job.onFinish = nil; job.cancel() }
        videoJobs.removeValue(forKey: id)?.cancel()
        if let gid = torrentJobs.removeValue(forKey: id) { Task { @MainActor in await self.torrentEngine.remove(gid) } }
        torrentStarting.remove(id)
        try? FileManager.default.removeItem(at: partURL(id))
        if trashFile, let saved = items.first(where: { $0.id == id })?.saved, FileManager.default.fileExists(atPath: saved.path) {
            do { try FileManager.default.trashItem(at: saved, resultingItemURL: nil) }
            catch { message = t("Dosya Çöp Sepeti’ne taşınamadı: ", "Could not move file to Trash: ") + error.localizedDescription }
        }
        items.removeAll { $0.id == id }; speeds[id] = nil; persist(); pump()
    }
    func remove(_ ids: Set<UUID>, trashFiles: Bool = false) { for id in ids { remove(id, trashFile: trashFiles) } }
    func start(_ ids: Set<UUID>) { for id in ids { start(id) } }
    func pause(_ ids: Set<UUID>) { for id in ids { pause(id) } }
    func resumeAll() { for item in items where item.canStart { start(item.id) } }
    func clearCompleted() { items.removeAll { $0.state == "Tamamlandı" }; persist() }
    func pauseAll() {
        for i in items.indices where ["Bekliyor", "Planlandı", "Yeniden denenecek"].contains(items[i].state) { items[i].state = "Duraklatıldı" }
        for item in items where item.state == "İndiriliyor" { pause(item.id) }
        persist()
    }

    /// Uygulama kapanırken: HTTP parçalarının son durumu kaydedilir, yt-dlp süreçleri durdurulur.
    func prepareForQuit() {
        for (id, job) in httpJobs {
            let (segments, total) = job.snapshot
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].segments = segments; items[i].total = total; items[i].state = "Duraklatıldı"
            }
            job.onFinish = nil; job.cancel()
        }
        httpJobs.removeAll()
        // aria2 Akıntı ile birlikte kapanır (--stop-with-process); devam bilgisi diskte kalır.
        for id in torrentJobs.keys { if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = "Duraklatıldı" } }
        torrentJobs.removeAll()
        torrentEngine.stop()
        stopVideoJobs()
    }
    func stopVideoJobs() {
        for (id, job) in videoJobs {
            job.terminateAndWait()
            if let i = items.firstIndex(where: { $0.id == id }) { items[i].state = "Duraklatıldı" }
        }
        videoJobs.removeAll()
        persist()
    }

    private func fail(_ i: Int, message: String, retryable: Bool) {
        items[i].error = message
        let count = items[i].retryCount ?? 0
        if retryable && count < preferences.retryLimit {
            items[i].retryCount = count + 1
            items[i].retryAt = Date().addingTimeInterval(pow(2, Double(count + 1)))
            items[i].state = "Yeniden denenecek"
        } else { items[i].state = "Hata" }
    }

    // MARK: HTTP indirmeleri (çok bağlantılı)

    private func startHTTP(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let job = HTTPJob(url: items[i].source, partURL: partURL(id), segments: items[i].segments, total: items[i].total,
                          connections: preferences.connectionsPerDownload, limiter: limiter)
        job.onProgress = { [weak self, weak job] segments, total in
            guard let self, let job, self.httpJobs[id] === job, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[i].segments = segments
            self.items[i].total = total
            self.items[i].received = segments.reduce(0) { $0 + min($1.received, $1.length) }
        }
        job.onFinish = { [weak self, weak job] result in
            guard let self, let job else { return }
            self.httpFinished(id, job: job, result: result)
        }
        httpJobs[id] = job
        items[i].state = "İndiriliyor"; items[i].error = nil
        job.start()
    }

    private func httpFinished(_ id: UUID, job: HTTPJob, result: HTTPJobResult) {
        guard httpJobs[id] === job else { return }
        httpJobs[id] = nil
        guard let i = items.firstIndex(where: { $0.id == id }) else { pump(); return }
        switch result {
        case .cancelled:
            items[i].state = "Duraklatıldı"
        case .failed(let message, _, let retryable):
            fail(i, message: message, retryable: retryable)
        case .finished(let suggested):
            do {
                let folder = items[i].destinationFolder ?? destinationFolder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let raw = suggested ?? items[i].name
                let name = URL(fileURLWithPath: raw).lastPathComponent
                let base = folder.appendingPathComponent(name.isEmpty ? t("İndirme", "Download") : name)
                var destination = base; var suffix = 1
                while FileManager.default.fileExists(atPath: destination.path) {
                    destination = folder.appendingPathComponent("\(base.deletingPathExtension().lastPathComponent) (\(suffix))").appendingPathExtension(base.pathExtension); suffix += 1
                }
                try FileManager.default.moveItem(at: partURL(id), to: destination)
                items[i].saved = destination; items[i].name = destination.lastPathComponent
                items[i].state = "Tamamlandı"; items[i].completedAt = Date(); items[i].segments = nil; items[i].error = nil
                if let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    items[i].received = Int64(size); items[i].total = Int64(size)
                }
            } catch { items[i].state = "Hata"; items[i].error = error.localizedDescription }
        }
        persist(); pump()
    }

    // MARK: Torrent indirmeleri (aria2)

    private func startTorrent(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        guard TorrentEngine.executable != nil else {
            items[i].state = "Hata"; items[i].error = TorrentEngine.EngineError.missing.errorDescription; return
        }
        let item = items[i]
        let folder = item.destinationFolder ?? destinationFolder
        items[i].state = "İndiriliyor"; items[i].error = nil
        torrentStarting.insert(id)
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await self.torrentEngine.start(seeding: self.preferences.torrentSeeding, speedLimit: Int64(self.preferences.speedLimitKB) * 1024)
                let gid: String
                if let data = item.torrentFile { gid = try await self.torrentEngine.addTorrent(data, folder: folder) }
                else { gid = try await self.torrentEngine.addURI(item.source.absoluteString, folder: folder) }
                self.torrentStarting.remove(id)
                // Bu arada duraklatıldı veya silindiyse aria2'den geri çıkar.
                guard let i = self.items.firstIndex(where: { $0.id == id }), self.items[i].state == "İndiriliyor" else {
                    await self.torrentEngine.remove(gid); self.pump(); return
                }
                self.torrentJobs[id] = gid
            } catch {
                self.torrentStarting.remove(id)
                if let i = self.items.firstIndex(where: { $0.id == id }) { self.fail(i, message: error.localizedDescription, retryable: false) }
                self.persist(); self.pump()
            }
        }
    }

    /// Saniyede bir aria2'den durum alınır: boyut, ilerleme, kaynak/eş sayısı, bitiş ve hatalar.
    private func pollTorrents() {
        guard !torrentJobs.isEmpty, !pollingTorrents else { return }
        pollingTorrents = true
        let jobs = torrentJobs
        Task { @MainActor in
            defer { self.pollingTorrents = false }
            var changed = false
            for (id, gid) in jobs {
                guard self.torrentJobs[id] == gid, let status = try? await self.torrentEngine.status(gid),
                      let i = self.items.firstIndex(where: { $0.id == id }) else { continue }
                let total = Int64(status["totalLength"] as? String ?? "") ?? 0
                let done = Int64(status["completedLength"] as? String ?? "") ?? 0
                let state = status["status"] as? String ?? ""
                if let next = (status["followedBy"] as? [String])?.first {
                    // Magnet/.torrent bağlantısı: önce üst veri iner, asıl indirme yeni bir GID ile sürer.
                    self.torrentJobs[id] = next; continue
                }
                if let name = TorrentEngine.name(from: status) { self.items[i].name = name }
                self.items[i].total = total
                self.items[i].received = done
                self.items[i].seeders = Int(status["numSeeders"] as? String ?? "")
                self.items[i].peers = Int(status["connections"] as? String ?? "")
                if let bitfield = status["bitfield"] as? String, let count = Int(status["numPieces"] as? String ?? ""), count > 0 {
                    self.items[i].pieceMap = TorrentEngine.pieceMap(bitfield: bitfield, pieces: count)
                }
                let folder = self.items[i].destinationFolder ?? self.destinationFolder
                if state == "complete" || (total > 0 && done >= total && (status["seeder"] as? String) == "true") {
                    self.items[i].saved = folder.appendingPathComponent(self.items[i].name)
                    self.items[i].state = "Tamamlandı"; self.items[i].completedAt = Date(); self.items[i].error = nil
                    self.items[i].pieceMap = nil
                    self.torrentJobs[id] = nil
                    if state == "complete" { _ = try? await self.torrentEngine.call("aria2.removeDownloadResult", [gid]) }
                    changed = true
                } else if state == "error" || state == "removed" {
                    self.torrentJobs[id] = nil
                    self.fail(i, message: status["errorMessage"] as? String ?? t("Torrent indirilemedi.", "The torrent download failed."), retryable: true)
                    changed = true
                }
            }
            if changed { self.persist(); self.pump() }
        }
    }

    // MARK: Video sitesi indirmeleri (yt-dlp)

    private func startVideo(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        guard let exe = VideoEngine.executable else {
            items[i].state = "Hata"; items[i].error = VideoEngine.EngineError.missing.errorDescription; return
        }
        let folder = items[i].destinationFolder ?? destinationFolder
        let quality = VideoQuality(rawValue: items[i].videoQuality ?? "") ?? .best
        let job = VideoJob(executable: exe, url: items[i].source, folder: folder, quality: quality, ffmpeg: VideoEngine.ffmpeg,
                           rateLimit: preferences.speedLimitKB > 0 ? Int64(preferences.speedLimitKB) * 1024 : nil,
                           fragments: preferences.connectionsPerDownload)
        job.onProgress = { [weak self, weak job] received, total in
            guard let self, let job, self.videoJobs[id] === job, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[i].received = received; self.items[i].total = total
        }
        job.onFinish = { [weak self, weak job] file, status, error in
            guard let self, let job else { return }
            self.videoFinished(id, job: job, file: file, status: status, error: error)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try job.start()
            videoJobs[id] = job
            items[i].state = "İndiriliyor"; items[i].error = nil
        } catch {
            items[i].state = "Hata"; items[i].error = error.localizedDescription
        }
    }

    private func videoFinished(_ id: UUID, job: VideoJob, file: URL?, status: Int32, error: String) {
        guard videoJobs[id] === job else { return }
        videoJobs[id] = nil
        guard let i = items.firstIndex(where: { $0.id == id }) else { pump(); return }
        if job.userCancelled {
            items[i].state = "Duraklatıldı"
        } else if status == 0, let file, FileManager.default.fileExists(atPath: file.path) {
            items[i].saved = file; items[i].name = file.lastPathComponent
            items[i].state = "Tamamlandı"; items[i].completedAt = Date(); items[i].error = nil
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                items[i].received = Int64(size); items[i].total = Int64(size)
            }
        } else {
            let text = error.isEmpty ? t("Video indirilemedi (çıkış kodu \(status)).", "Video download failed (exit code \(status)).") : error
            let lower = text.lowercased()
            fail(i, message: text, retryable: lower.contains("http error 5") || lower.contains("timed out") || lower.contains("connection"))
        }
        persist(); pump()
    }
}
