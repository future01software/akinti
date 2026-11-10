import SwiftUI
import AppKit

struct AddLinksView: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var schedule = false
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var mode: LinkMode = .auto
    @State private var quality: VideoQuality = .p1080
    @State private var infos: [URL: VideoInfo] = [:]
    @State private var probeErrors: [URL: String] = [:]
    @ObservedObject private var tools = ToolManager.shared
    @State private var hasEngine = VideoEngine.executable != nil
    @State private var hasFFmpeg = VideoEngine.ffmpeg != nil
    @State private var wholePlaylist = true

    private var links: [URL] { DownloadStore.links(in: text) }
    private var torrentLinks: [URL] { links.filter { TorrentEngine.isMagnet($0) || (mode != .file && TorrentEngine.isTorrentLink($0)) } }
    private var videoLinks: [URL] { links.filter { !torrentLinks.contains($0) && mode.treatsAsVideo($0) } }
    /// Hem tek video hem liste içeren bağlantılar (watch?v=…&list=…): kullanıcı seçer.
    private var mixedPlaylists: [VideoInfo] { videoLinks.compactMap { url in infos[url].flatMap { $0.isPlaylist && VideoEngine.hasSingleVideo(url) ? $0 : nil } } }
    /// Liste bilgisi gelmeden eklenirse tüm liste tek indirme olurdu; bu yüzden beklenir.
    private var waitingForPlaylist: Bool {
        hasEngine && videoLinks.contains { VideoEngine.isPlaylist($0) && infos[$0] == nil && probeErrors[$0] == nil }
    }
    /// Eklenecek bağlantılar: listeler videolarına açılır.
    private var expanded: (urls: [URL], titles: [URL: String]) {
        var urls: [URL] = [], titles: [URL: String] = [:]
        for link in links {
            if let info = infos[link], mode.treatsAsVideo(link), info.isPlaylist, wholePlaylist || !VideoEngine.hasSingleVideo(link) {
                for entry in info.entries { urls.append(entry.url); titles[entry.url] = entry.title }
            } else {
                urls.append(link)
                if let info = infos[link], !info.isPlaylist { titles[link] = info.title }
            }
        }
        return (urls, titles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down").font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Yeni indirme", "New Download")).font(.title2.bold())
                    Text(t("Dosya, video sayfası (YouTube, Vimeo…) veya magnet bağlantılarını yapıştırın; her satıra bir bağlantı.",
                           "Paste file, video page (YouTube, Vimeo…) or magnet links, one per line.")).font(.callout).foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 90)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))

            if !links.isEmpty { preview }

            if !videoLinks.isEmpty && !hasEngine { installBox }
            if torrentLinks.count > 0 && TorrentEngine.executable == nil {
                Label(t("Torrent için aria2 gerekli. Terminal’de: ", "Torrents need aria2. In Terminal: ") + TorrentEngine.installCommand, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }

            Form {
                Picker(t("Bağlantı türü", "Link type"), selection: $mode) {
                    ForEach(LinkMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if let list = mixedPlaylists.first {
                    Toggle(t("Oynatma listesinin tamamını indir (\(list.entries.count) video)", "Download the whole playlist (\(list.entries.count) videos)"), isOn: $wholePlaylist)
                }
                if !videoLinks.isEmpty {
                    Picker(t("Video kalitesi", "Video quality"), selection: $quality) {
                        ForEach(VideoQuality.allCases) { q in
                            Text(q.title).tag(q)
                            if q == .p480 { Divider() }
                        }
                    }
                }
                LabeledContent(t("Kaydet", "Save to")) {
                    HStack {
                        Label(store.destinationFolder.lastPathComponent, systemImage: "folder").help(store.destinationFolder.path)
                        Button(t("Değiştir…", "Change…")) { FolderPicker.choose(for: store) }
                    }
                }
                Toggle(t("Belirli saatte başlat", "Start at a specific time"), isOn: $schedule)
                if schedule {
                    DatePicker(t("Başlangıç", "Start"), selection: $scheduledAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
            }
            .formStyle(.grouped).scrollDisabled(true)
            .frame(height: 150 + (videoLinks.isEmpty ? 0 : 40) + (mixedPlaylists.isEmpty ? 0 : 40) + (schedule ? 40 : 0))
            .padding(.horizontal, -20)

            if !videoLinks.isEmpty && hasEngine && !hasFFmpeg && !tools.isInstalling(.ffmpeg) {
                Button(t("Yüksek kalite için ffmpeg’i kur", "Install ffmpeg for high quality")) { Task { await installVideoTools() } }
                    .buttonStyle(.link)
            }
            if !videoLinks.isEmpty && hasEngine && !hasFFmpeg {
                Text(t("ffmpeg kurulu değil: yüksek kaliteli görüntü ve ses birleştirilemez, tek dosyalık en iyi sürüm (çoğunlukla 720p) indirilir; MP3 yerine M4A kaydedilir.",
                       "ffmpeg is not installed: high-quality video and audio can’t be merged, so the best single-file version (often 720p) is downloaded, and M4A is saved instead of MP3."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if schedule {
                Text(t("Zamanında başlaması için Akıntı açık, Mac uyanık olmalıdır.", "Akıntı must be open and the Mac awake for it to start on time.")).font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Button(t("Panodan yapıştır", "Paste from Clipboard")) { text = NSPasteboard.general.string(forType: .string) ?? text }
                Button(t("Torrent dosyası…", "Torrent File…")) { if TorrentFilePicker.choose(for: store) { close() } }
                Spacer()
                Button(t("Vazgeç", "Cancel")) { close() }.keyboardShortcut(.cancelAction)
                if waitingForPlaylist {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(t("Liste okunuyor…", "Reading playlist…")) }
                        .font(.callout).foregroundStyle(.secondary)
                } else if expanded.urls.count > links.count {
                    Text(t("\(expanded.urls.count) indirme eklenecek", "\(expanded.urls.count) downloads will be added")).font(.callout).foregroundStyle(.secondary)
                }
                Button(t("Sonra indir", "Download Later")) { submit(paused: true) }.disabled(links.isEmpty || schedule || waitingForPlaylist)
                    .help(t("Listeye duraklatılmış olarak ekler", "Adds to the list paused"))
                Button(schedule ? t("Planla", "Schedule") : t("İndir", "Download")) { submit(paused: false) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(links.isEmpty || waitingForPlaylist)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            if !store.pendingLinks.isEmpty { text = store.pendingLinks }
            else if let clip = NSPasteboard.general.string(forType: .string), !DownloadStore.links(in: clip).isEmpty {
                text = DownloadStore.links(in: clip).map(\.absoluteString).joined(separator: "\n")
            }
            store.pendingLinks = ""
        }
        .task(id: videoLinks) { await probeVideos() }
    }

    // MARK: Önizleme

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("\(links.count) bağlantı bulundu", "\(links.count) link(s) found")).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(links.prefix(5).enumerated()), id: \.offset) { _, url in
                if torrentLinks.contains(url) { torrentRow(url) } else if mode.treatsAsVideo(url) { videoRow(url) } else { fileRow(url) }
            }
            if links.count > 5 { Text(t("+\(links.count - 5) daha", "+\(links.count - 5) more")).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func fileRow(_ url: URL) -> some View {
        let name = url.lastPathComponent.isEmpty ? t("İndirme", "Download") : url.lastPathComponent
        return HStack(spacing: 8) {
            FileIcon(category: FileCategory.of(name), size: 22)
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(url.host ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func torrentRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            FileIcon(category: .torrents, size: 22)
            Text(TorrentEngine.displayName(url)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(TorrentEngine.isMagnet(url) ? "Magnet" : "Torrent").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func videoRow(_ url: URL) -> some View {
        let info = infos[url]
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let thumb = info?.thumbnail {
                    AsyncImage(url: thumb) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                } else {
                    Image(systemName: quality.isAudio ? "music.note" : "play.rectangle.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                if let info, info.isPlaylist {
                    Label(info.title, systemImage: "list.and.film").lineLimit(1).truncationMode(.tail)
                    Text([info.site, t("Oynatma listesi · \(info.entries.count) video", "Playlist · \(info.entries.count) videos")].joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                } else if let info {
                    Text(info.title).lineLimit(1).truncationMode(.tail)
                    Text([info.site, info.duration.map { Format.eta($0) }, info.maxHeight.map { t("en fazla \($0)p", "up to \($0)p") }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                } else if let error = probeErrors[url] {
                    Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).lineLimit(2)
                } else {
                    Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
                    if hasEngine {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(t("Video bilgisi alınıyor…", "Fetching video info…")) }
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(t("Video sayfası", "Video page")).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var installBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(t("Video indirmek için bir bileşen gerekli", "A component is needed to download videos"), systemImage: "puzzlepiece.extension")
                .font(.headline)
            Text(t("Akıntı, YouTube ve yüzlerce siteden video indiren açık kaynak yt-dlp’yi ve görüntü/ses birleştiren ffmpeg’i resmi kaynaklarından indirip doğrular (yaklaşık 65 MB). Homebrew gerekmez.",
                   "Akıntı downloads and verifies the open-source yt-dlp (video from YouTube and hundreds of sites) and ffmpeg (merges video and audio) from their official sources (about 65 MB). No Homebrew needed."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if tools.isInstalling(.ytdlp) || tools.isInstalling(.ffmpeg) {
                    ProgressView(value: tools.progress[.ytdlp] ?? tools.progress[.ffmpeg] ?? 0).frame(width: 180)
                    Text(tools.isInstalling(.ytdlp) ? "yt-dlp…" : "ffmpeg…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button { Task { await installVideoTools() } } label: { Label(t("Kur", "Install"), systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            if let error = tools.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func installVideoTools() async {
        await tools.installMissing([.ytdlp, .ffmpeg])
        hasEngine = VideoEngine.executable != nil
        hasFFmpeg = VideoEngine.ffmpeg != nil
        await probeVideos()
    }

    // MARK: İşlemler

    private func probeVideos() async {
        guard hasEngine else { return }
        // Yazarken her tuşta yt-dlp başlatmamak için kısa bekleme; bağlantı değişirse görev iptal olur.
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        await withTaskGroup(of: (URL, Result<VideoInfo, Error>).self) { group in
            for url in videoLinks.prefix(5) where infos[url] == nil && probeErrors[url] == nil {
                group.addTask {
                    do { return (url, .success(try await VideoEngine.probe(url))) } catch { return (url, .failure(error)) }
                }
            }
            for await (url, result) in group {
                switch result {
                case .success(let info): infos[url] = info
                case .failure(let error): probeErrors[url] = error.localizedDescription
                }
            }
        }
    }

    private func submit(paused: Bool) {
        let (urls, titles) = expanded
        let joined = urls.map(\.absoluteString).joined(separator: "\n")
        if store.add(joined, scheduledAt: schedule ? scheduledAt : nil, startPaused: paused, mode: mode, quality: quality, titles: titles) { close() }
    }

    private func close() {
        store.pendingLinks = ""
        dismiss()
    }
}

enum TorrentFilePicker {
    /// .torrent dosyası seçtirir ve ekler. Eklendiyse true döner.
    @discardableResult
    static func choose(for store: DownloadStore) -> Bool {
        let panel = NSOpenPanel()
        panel.title = t("Torrent dosyası seçin", "Choose torrent files")
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        panel.allowsMultipleSelection = true
        panel.prompt = t("Ekle", "Add")
        guard panel.runModal() == .OK else { return false }
        return panel.urls.map { store.addTorrentFile($0) }.contains(true)
    }
}

enum FolderPicker {
    static func choose(for store: DownloadStore) {
        let panel = NSOpenPanel()
        panel.title = t("İndirmelerin kaydedileceği klasörü seçin", "Choose where downloads are saved")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.destinationFolder
        panel.prompt = t("Seç", "Choose")
        if panel.runModal() == .OK, let folder = panel.url { _ = store.chooseDestination(folder) }
    }
}
