import SwiftUI
import AkintiShared
import AppKit

struct ContentView: View {
    @ObservedObject var store: DownloadStore
    @State private var sidebar: SidebarSelection? = .all
    @State private var search = ""
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\Download.addedDate)]
    @State private var confirmTrash = false
    @State private var lastPasteboardChange = NSPasteboard.general.changeCount
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var current: SidebarSelection { sidebar ?? .all }
    private var visible: [Download] {
        store.items
            .filter { current.matches($0) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.source.host ?? "").localizedCaseInsensitiveContains(search)) }
            .sorted(using: sortOrder)
    }
    private var selectedItems: [Download] { store.items.filter { selection.contains($0.id) } }
    private var activeCount: Int { store.items.filter { $0.state == "İndiriliyor" }.count }
    private var queuedCount: Int { store.items.filter { StatusFilter.queued.matches($0) }.count }
    private var finishedCount: Int { store.items.filter { $0.state == "Tamamlandı" }.count }

    var body: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            VStack(spacing: 0) {
                table
                if selectedItems.count == 1, let item = selectedItems.first {
                    Divider()
                    DetailPanel(store: store, item: item)
                }
                Divider()
                statusBar
            }
            .navigationTitle(current.title)
            .navigationSubtitle(activeCount > 0 ? t("\(activeCount) aktif", "\(activeCount) active") + " · \(Format.speed(store.totalSpeed))" : t("\(visible.count) öğe", "\(visible.count) items"))
            .searchable(text: $search, placement: .toolbar, prompt: t("Dosya veya site ara", "Search files or sites"))
            .toolbar { toolbarContent }
            .dropDestination(for: URL.self) { urls, _ in
                let torrents = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "torrent" }
                for file in torrents { store.addTorrentFile(file) }
                let links = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") || TorrentEngine.isMagnet($0) }
                guard !links.isEmpty else { return !torrents.isEmpty }
                store.pendingLinks = links.map(\.absoluteString).joined(separator: "\n")
                store.isAdding = true
                return true
            }
        }
        .frame(minWidth: 960, minHeight: 560)
        .sheet(isPresented: $store.isAdding) { AddLinksView(store: store) }
        .sheet(isPresented: $store.isShowingHelp) { QuickStartView() }
        .alert(t("Akıntı güncellemesi hazır", "Akıntı update available"), isPresented: $updater.promptVisible, presenting: updater.available) { release in
            Button(t("Şimdi güncelle", "Update Now")) { Task { await updater.install(release) } }
            Button(t("Sürüm notları", "Release Notes")) { NSWorkspace.shared.open(release.pageURL) }
            Button(t("Sonra", "Later"), role: .cancel) {}
        } message: { release in
            Text(t("Akıntı \(release.version) çıktı (sizdeki \(Updater.currentVersion)). Güncelleme indirilip doğrulanır; Akıntı kapanıp yeni sürümle açılır, indirmeleriniz korunur.",
                   "Akıntı \(release.version) is out (you have \(Updater.currentVersion)). The update is downloaded and verified; Akıntı restarts with the new version and your downloads are kept."))
        }
        .sheet(isPresented: Binding(get: { updater.isBusyInstalling }, set: { _ in })) { UpdateProgressView(updater: updater) }
        .alert("Akıntı", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(t("Tamam", "OK")) { store.message = nil }
        } message: { Text(store.message ?? "") }
        .confirmationDialog(t("Seçilen \(selection.count) indirme kaldırılsın mı?", "Remove \(selection.count) selected download(s)?"), isPresented: $confirmTrash) {
            Button(t("Yalnızca listeden kaldır", "Remove from list only")) { removeSelection(trash: false) }
            Button(t("Dosyaları Çöp Sepeti’ne taşı", "Move files to Trash"), role: .destructive) { removeSelection(trash: true) }
        } message: { Text(t("Çöp Sepeti’ne taşınan dosyalar Finder’dan geri alınabilir.", "Files moved to Trash can be restored from Finder.")) }
        .onChange(of: activeCount) { _, n in NSApp?.dockTile.badgeLabel = n > 0 ? "\(n)" : nil }
        .onChange(of: store.popupRequests) { _, _ in openRequestedPopups() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in captureClipboard() }
        .onAppear {
            MainWindow.openAction = openWindow
            MainWindow.settingsAction = openSettings
            NSApp.setActivationPolicy(.regular) // ana pencere görünürken Dock simgesi her zaman vardır
            openRequestedPopups() // pencere açılmadan önce eklenen indirmeler için
            // Geliştirici seçeneği: --select-first ilk satırı seçer (ayrıntı panelini denemek için).
            if CommandLine.arguments.contains("--select-first"), let first = visible.first(where: { $0.state == "İndiriliyor" }) ?? visible.first { selection = [first.id] }
            // Geliştirici seçeneği: --debug-install-update <zip> <sürüm> — güncelleyiciyi yerel bir paketle uçtan uca dener.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--debug-install-update"), i + 2 < args.count {
                let zip = URL(fileURLWithPath: args[i + 1])
                let release = Updater.Release(version: args[i + 2], notes: "", pageURL: zip, zipURL: zip,
                                              sha256: (try? ToolManager.sha256(of: zip)).map { "sha256:" + $0 })
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Task { await Updater.shared.install(release) } }
            }
            if CommandLine.arguments.contains("--show-about") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AboutPanel.show() }
            }
            if CommandLine.arguments.contains("--open-settings") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { openSettings() }
            }
        }
    }

    // MARK: Kenar çubuğu

    private var sidebarList: some View {
        List(selection: $sidebar) {
            Label(t("Tüm indirmeler", "All Downloads"), systemImage: "tray.full")
                .badge(store.items.count).tag(SidebarSelection.all)
            Section(t("Kategoriler", "Categories")) {
                ForEach(FileCategory.allCases) { c in
                    Label { Text(c.title) } icon: { Image(systemName: c.symbol).foregroundStyle(c.tint) }
                        .badge(store.items.filter { $0.category == c }.count)
                        .tag(SidebarSelection.category(c))
                }
            }
            Section(t("Durum", "Status")) {
                ForEach(StatusFilter.allCases) { s in
                    Label(s.title, systemImage: s.symbol)
                        .badge(store.items.filter { s.matches($0) }.count)
                        .tag(SidebarSelection.status(s))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .safeAreaInset(edge: .bottom) { speedCard }
    }

    private var speedCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down").font(.headline).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(activeCount > 0 ? Color.accentColor : Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(activeCount > 0 ? Format.speed(store.totalSpeed) : t("Boşta", "Idle")).font(.headline.monospacedDigit())
                Text(t("\(activeCount) aktif · \(queuedCount) kuyrukta", "\(activeCount) active · \(queuedCount) queued")).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }

    // MARK: Tablo

    private var table: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(t("Dosya adı", "Name"), value: \.name) { d in
                HStack(spacing: 8) {
                    FileIcon(category: d.category, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name).lineLimit(1).truncationMode(.middle)
                        Text(d.isTorrent == true ? (TorrentEngine.isMagnet(d.source) ? "Magnet" : "Torrent") : d.source.host ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.vertical, 3)
            }.width(min: 180, ideal: 250)
            TableColumn(t("Boyut", "Size"), value: \.total) { d in
                Text(d.total > 0 ? Format.bytes(d.total) : "—").monospacedDigit().foregroundStyle(.secondary)
            }.width(min: 60, ideal: 75)
            TableColumn(t("Durum", "Status"), value: \.state) { d in StatusCell(item: d) }
                .width(min: 130, ideal: 160)
            TableColumn(t("Hız", "Speed")) { d in
                Text(store.speeds[d.id].map(Format.speed) ?? "").monospacedDigit().foregroundStyle(.secondary)
            }.width(min: 60, ideal: 75)
            TableColumn(t("Kalan süre", "Time left")) { d in
                Text(store.eta(for: d).map(Format.eta) ?? "").monospacedDigit().foregroundStyle(.secondary)
            }.width(min: 60, ideal: 75)
            TableColumn(t("Eklenme", "Added"), value: \.addedDate) { d in
                Text(d.addedAt.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) } ?? "—").foregroundStyle(.secondary)
            }.width(min: 100, ideal: 125)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            for d in store.items where ids.contains(d.id) {
                if let saved = d.saved { NSWorkspace.shared.open(saved) } else if d.canStart { store.start(d.id) }
            }
        }
        .onDeleteCommand { if !selection.isEmpty { confirmTrash = true } }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? t("Henüz indirme yok", "No downloads yet") : t("Sonuç bulunamadı", "No results"),
                          systemImage: search.isEmpty ? "arrow.down.circle" : "magnifyingglass")
                } description: {
                    Text(search.isEmpty
                         ? t("Bir indirme bağlantısını kopyalayıp ⌘N’ye basın veya bağlantıyı bu pencereye sürükleyin.", "Copy a download link and press ⌘N, or drag the link into this window.")
                         : t("Farklı bir arama deneyin.", "Try a different search."))
                } actions: {
                    if search.isEmpty { Button(t("Bağlantı ekle", "Add Link")) { store.isAdding = true }.buttonStyle(.borderedProminent) }
                }
            }
        }
    }

    @ViewBuilder private func contextMenu(for ids: Set<UUID>) -> some View {
        let items = store.items.filter { ids.contains($0.id) }
        if let single = items.first, items.count == 1, let saved = single.saved {
            Button(t("Aç", "Open")) { NSWorkspace.shared.open(saved) }
            Button(t("Finder’da göster", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
            Divider()
        }
        Button(t("Devam et", "Resume"), systemImage: "play.fill") { store.start(ids) }.disabled(!items.contains { $0.canStart })
        Button(t("Duraklat", "Pause"), systemImage: "pause.fill") { store.pause(ids) }.disabled(!items.contains { $0.canPause })
        Divider()
        Button(t("Bağlantıyı kopyala", "Copy Link"), systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(items.map(\.source.absoluteString).joined(separator: "\n"), forType: .string)
            lastPasteboardChange = NSPasteboard.general.changeCount
        }
        Divider()
        Button(t("Listeden kaldır", "Remove from List"), systemImage: "minus.circle") { selection = ids; removeSelection(trash: false) }
        Button(t("Dosyayla birlikte sil…", "Delete with File…"), systemImage: "trash", role: .destructive) { selection = ids; confirmTrash = true }
    }

    // MARK: Araç çubuğu ve durum çubuğu

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { store.isAdding = true } label: { Label(t("Bağlantı ekle", "Add Link"), systemImage: "plus") }
                .help(t("Yeni indirme ekle (⌘N)", "Add a new download (⌘N)"))
        }
        ToolbarItemGroup {
            Button { store.start(selection) } label: { Label(t("Devam et", "Resume"), systemImage: "play.fill") }
                .help(t("Seçilenleri başlat / devam ettir", "Start / resume selected")).disabled(!selectedItems.contains { $0.canStart })
            Button { store.pause(selection) } label: { Label(t("Duraklat", "Pause"), systemImage: "pause.fill") }
                .help(t("Seçilenleri duraklat", "Pause selected")).disabled(!selectedItems.contains { $0.canPause })
            Button { confirmTrash = true } label: { Label(t("Kaldır", "Remove"), systemImage: "trash") }
                .help(t("Seçilenleri kaldır", "Remove selected")).disabled(selection.isEmpty)
        }
        ToolbarItemGroup {
            Menu {
                Button(t("Tümünü başlat", "Start All"), systemImage: "play.circle") { store.resumeAll() }
                Button(t("Tümünü duraklat", "Pause All"), systemImage: "pause.circle") { store.pauseAll() }
                Divider()
                Button(t("Tamamlananları listeden temizle", "Clear Completed"), systemImage: "checkmark.circle.badge.xmark") { store.clearCompleted() }
                    .disabled(finishedCount == 0)
                Button(t("İndirme klasörünü aç", "Open Download Folder"), systemImage: "folder") { openDestination() }
            } label: { Label(t("Kuyruk", "Queue"), systemImage: "list.bullet.rectangle") }
            .help(t("Kuyruk işlemleri", "Queue actions"))
            SettingsLink { Label(t("Ayarlar", "Settings"), systemImage: "gearshape") }.help(t("Ayarlar (⌘,)", "Settings (⌘,)"))
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label(Format.speed(store.totalSpeed), systemImage: "arrow.down").monospacedDigit()
            Text(t("\(activeCount) indiriliyor · \(queuedCount) kuyrukta · \(finishedCount) tamamlandı",
                   "\(activeCount) downloading · \(queuedCount) queued · \(finishedCount) finished"))
            Spacer()
            Menu {
                Picker(t("Hız sınırı", "Speed limit"), selection: $store.preferences.speedLimitKB) {
                    ForEach(SpeedLimit.options, id: \.self) { Text(SpeedLimit.title($0)).tag($0) }
                }.pickerStyle(.inline)
            } label: {
                Label(store.preferences.speedLimitKB == 0 ? t("Sınırsız", "Unlimited") : SpeedLimit.title(store.preferences.speedLimitKB),
                      systemImage: store.preferences.speedLimitKB == 0 ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.33percent")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .foregroundStyle(store.preferences.speedLimitKB == 0 ? Color.secondary : Color.orange)
            .help(t("Toplam hız sınırı", "Total speed limit"))
            Button { openDestination() } label: { Label(store.destinationFolder.lastPathComponent, systemImage: "folder") }
                .buttonStyle(.borderless).help(store.destinationFolder.path)
            Picker(t("Aynı anda", "Simultaneous"), selection: $store.limit) { ForEach(1...8, id: \.self) { Text("\($0)").tag($0) } }
                .pickerStyle(.menu).fixedSize()
        }
        .font(.body).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.bar)
    }

    // MARK: Yardımcılar

    private func openRequestedPopups() {
        let ids = store.popupRequests
        guard !ids.isEmpty else { return }
        store.popupRequests = []
        for id in ids { openWindow(id: "download", value: id) }
    }

    private func removeSelection(trash: Bool) {
        store.remove(selection, trashFiles: trash)
        selection.removeAll()
    }

    private func openDestination() {
        do {
            try FileManager.default.createDirectory(at: store.destinationFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.destinationFolder)
        } catch { store.message = error.localizedDescription }
    }

    /// IDM gibi: kopyalanan dosya bağlantısını yakalar ve ekleme penceresini açar.
    private func captureClipboard() {
        let pasteboard = NSPasteboard.general
        guard store.preferences.clipboardCapture, !store.isAdding, pasteboard.changeCount != lastPasteboardChange else { return }
        lastPasteboardChange = pasteboard.changeCount
        let known = Set(store.items.map(\.source))
        let links = DownloadStore.links(in: pasteboard.string(forType: .string) ?? "")
            .filter { (FileCategory.of($0.lastPathComponent) != .other || VideoEngine.isVideoPage($0) || TorrentEngine.isMagnet($0)) && !known.contains($0) }
        guard !links.isEmpty else { return }
        store.pendingLinks = links.map(\.absoluteString).joined(separator: "\n")
        store.isAdding = true
    }
}

// MARK: - Bileşenler

struct FileIcon: View {
    let category: FileCategory
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

struct StatusCell: View {
    let item: Download
    var body: some View {
        if item.state == "İndiriliyor" {
            HStack(spacing: 8) {
                ProgressView(value: item.progress).progressViewStyle(.linear).controlSize(.small)
                Text(item.total > 0 ? Format.percent(item.progress) : Format.bytes(item.received))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 34, alignment: .trailing)
            }
        } else {
            HStack(spacing: 6) {
                Circle().fill(Self.color(item.state)).frame(width: 7, height: 7)
                Text(label).lineLimit(1)
            }
            .help(item.error ?? "")
        }
    }
    private var label: String {
        let title = L10n.state(item.state)
        switch item.state {
        case "Planlandı": return item.scheduledAt.map { "\(title) · \($0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))" } ?? title
        case "Yeniden denenecek": return "\(title) (\(item.retryCount ?? 0))"
        case "Duraklatıldı" where item.total > 0: return "\(title) · \(Format.percent(item.progress))"
        default: return title
        }
    }
    static func color(_ state: String) -> Color {
        switch state {
        case "Tamamlandı": return .green
        case "Hata": return .red
        case "Duraklatıldı", "Duraklatılıyor": return .orange
        case "Planlandı", "Bekliyor", "Yeniden denenecek": return .blue
        default: return .secondary
        }
    }
}

/// Seçili indirmenin ayrıntıları (IDM'in indirme penceresinin sade karşılığı).
struct DetailPanel: View {
    @ObservedObject var store: DownloadStore
    let item: Download
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            FileIcon(category: item.category, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(item.source.absoluteString).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                if let map = item.pieceMap, item.state != "Tamamlandı" {
                    PieceBar(map: map, tint: StatusCell.color(item.state) == .secondary ? Color.accentColor : StatusCell.color(item.state))
                } else if let segments = item.segments, segments.count > 1, item.state != "Tamamlandı" {
                    SegmentBar(segments: segments, tint: StatusCell.color(item.state) == .secondary ? Color.accentColor : StatusCell.color(item.state))
                } else {
                    ProgressView(value: item.state == "Tamamlandı" ? 1 : item.progress)
                        .tint(StatusCell.color(item.state) == .secondary ? Color.accentColor : StatusCell.color(item.state))
                }
                HStack(spacing: 20) {
                    stat(t("Durum", "Status"), L10n.state(item.state))
                    stat(t("İndirilen", "Downloaded"), item.total > 0 ? "\(Format.bytes(item.received)) / \(Format.bytes(item.total))" : Format.bytes(item.received))
                    if let s = store.speeds[item.id] { stat(t("Hız", "Speed"), Format.speed(s)) }
                    if let eta = store.eta(for: item) { stat(t("Kalan", "Left"), Format.eta(eta)) }
                    if let segments = item.segments, segments.count > 1, item.state != "Tamamlandı" {
                        stat(t("Bağlantı", "Connections"), "\(segments.filter { !$0.isDone }.count) / \(segments.count)")
                    }
                    if item.isTorrent == true, item.state == "İndiriliyor" {
                        stat(t("Kaynak / Eş", "Seeds / Peers"), "\(item.seeders ?? 0) / \(item.peers ?? 0)")
                    }
                    stat(t("Klasör", "Folder"), (item.destinationFolder ?? store.destinationFolder).lastPathComponent)
                }
                if let error = item.error, item.state != "Tamamlandı" {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if let saved = item.saved {
                    Button(t("Aç", "Open")) { NSWorkspace.shared.open(saved) }.buttonStyle(.borderedProminent)
                    Button(t("Finder’da göster", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([saved]) }
                } else if item.canStart {
                    Button { store.start(item.id) } label: { Label(t("Devam et", "Resume"), systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                } else if item.canPause {
                    Button { store.pause(item.id) } label: { Label(t("Duraklat", "Pause"), systemImage: "pause.fill") }
                }
            }.controlSize(.large)
        }
        .padding(16)
        .background(.background.secondary)
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.tertiary)
            Text(value).font(.callout.monospacedDigit()).lineLimit(1)
        }
    }
}

/// IDM'deki gibi: her bağlantının dosyanın hangi bölümünü indirdiğini gösteren çubuk.
struct SegmentBar: View {
    let segments: [Segment]
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.reduce(0) { $0 + $1.length })
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    let width = max(2, (geo.size.width - CGFloat(segments.count - 1) * 2) * CGFloat(s.length) / CGFloat(total))
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.quaternary)
                        Rectangle().fill(tint).frame(width: width * CGFloat(min(1, Double(s.received) / Double(max(1, s.length)))))
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(t("Her bölüm ayrı bir bağlantıyla indirilir", "Each part is downloaded over its own connection"))
    }
}

/// Torrent parça haritası: her çizgi dosyanın bir bölümü; dolu = indi, yarı saydam = kısmen indi.
struct PieceBar: View {
    let map: [Double]
    let tint: Color
    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(map.enumerated()), id: \.offset) { _, v in
                Rectangle().fill(v >= 1 ? tint : (v > 0 ? tint.opacity(0.25 + 0.5 * v) : Color.secondary.opacity(0.2)))
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(t("Parça haritası: torrent parçaları birçok eşten aynı anda iner", "Piece map: torrent pieces arrive from many peers at once"))
    }
}

// MARK: - Uygulama

/// Tarayıcıda tıklanan magnet bağlantıları ve Finder'dan açılan .torrent dosyaları buraya gelir.
/// Web sayfaları kendi başına indirme başlatamasın diye magnet bağlantıları önce ekleme penceresinde gösterilir.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var store: DownloadStore?
    static var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock'un "Çık" komutunu kapanma süreci başlamadan karşıla (AppKit'in kendi işleyicisinin yerine).
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuitEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
        // "Yalnızca menü çubuğunda" kipinde ana pencere kapanınca Dock simgesi gizlenir.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, MainWindow.isMainWindow(window) else { return }
            DispatchQueue.main.async { Self.updateDockIcon() }
        }
        NotificationCenter.default.addObserver(forName: DownloadStore.dockPolicyChanged, object: nil, queue: .main) { _ in Self.updateDockIcon() }
        // Menü çubuğu simgesi ve paneli
        if let store = Self.store { Self.statusItem = StatusItemController(store: store) }
        // Tarayıcı eklentisi köprüsünü kurulu Chrome/Brave/Edge/Arc… tarayıcılarına kaydet (uygulama taşınırsa yolu günceller).
        BrowserBridge.register()
        BrowserBridge.syncInstalledExtension()
        Updater.removeLeftovers()
        // Akıntı'nın yeni sürümü günde bir kez denetlenir (açılıştan biraz sonra).
        if Self.store?.preferences.autoCheckUpdates == true {
            Task { @MainActor in try? await Task.sleep(nanoseconds: 3_000_000_000); await Updater.shared.check(userInitiated: false) }
        }
        // YouTube sık değiştiği için Akıntı'nın kurduğu yt-dlp günde bir kez denetlenip güncellenir.
        if Self.store?.preferences.autoUpdateTools == true {
            Task { @MainActor in await ToolManager.shared.updateYtDlpIfNeeded() }
        }
    }

    static func updateDockIcon() {
        guard let prefs = store?.preferences else { return }
        let hide = prefs.menuBarOnly && prefs.showMenuBarIcon && MainWindow.existing == nil
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }

    /// Dock'tan "Çık": menü çubuğu simgesi açıksa uygulama kapanmaz; pencereler kapanır, Dock simgesi gizlenir.
    /// ⌘Q ve menü çubuğundaki "Akıntı'dan çık" gerçekten kapatır; oturum kapatma/yeniden başlatma her zaman kapatır.
    ///
    /// Not: Bu, `applicationShouldTerminate` içinde iptal edilerek yapılmaz. Kapanma süreci bir kez başlayınca
    /// SwiftUI sahnelerini kapatmaya hazırlanıyor; iptal edilince menü çubuğu simgesi kalsa da paneli açılmıyordu.
    /// Bu yüzden "çık" Apple olayı, kapanma hiç başlamadan burada karşılanır.
    @objc func handleQuitEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        if let prefs = Self.store?.preferences, prefs.showMenuBarIcon, prefs.keepRunningOnDockQuit,
           Self.isQuitAppleEventWithoutReason(event) {
            Self.moveToMenuBar()
        } else {
            NSApp.terminate(nil)
        }
    }

    /// Pencereleri kapatır ve Dock simgesini gizler; menü çubuğu simgesi ve indirmeler sürer.
    static func moveToMenuBar() {
        for window in NSApp.windows where window.isVisible && window.level == .normal { window.close() }
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    /// Dock (veya başka bir uygulama) "çık" Apple olayı gönderdiyse true. ⌘Q ve menüden çıkışta olay yoktur;
    /// oturum kapatma, yeniden başlatma ve kapatmada olayın içinde bir "çıkış nedeni" bulunur.
    nonisolated static func isQuitAppleEventWithoutReason(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEQuitApplication) else { return false }
        return event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil
    }

    /// Dock simgesine tıklanınca pencere yoksa SwiftUI yeni ana pencere açar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let store = Self.store else { return }
        var links: [URL] = []
        for url in urls {
            if let link = AkintiLink.parse(url) {
                // Tarayıcı eklentisi: bağlantılar ve ek bilgiler ekleme penceresine gelir (kendiliğinden indirilmez).
                links += link.urls
                store.pendingReferrer = link.referrer
                store.pendingUserAgent = link.userAgent
                store.pendingVideoMode = link.mode == "video"
            } else if url.isFileURL, url.pathExtension.lowercased() == "torrent" { store.addTorrentFile(url) }
            else if TorrentEngine.isMagnet(url) || ["http", "https"].contains(url.scheme?.lowercased() ?? "") { links.append(url) }
        }
        if !links.isEmpty {
            store.pendingLinks = links.map(\.absoluteString).joined(separator: "\n")
            store.isAdding = true
            if MainWindow.existing == nil { store.mainWindowRequest += 1 }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Uygulamanın en üst yapısının izlediği, seyrek değişen durum (menü çubuğu simgesi ve dil).
/// İndirme listesi saniyede birkaç kez değiştiği için App bunu doğrudan izlemez; izleseydi
/// menü çubuğu öğesi ve menüler sürekli yeniden kurulur, açılan panel bozulurdu.
final class AppChrome: ObservableObject {
    @Published var language: String
    private weak var store: DownloadStore?
    private var observer: NSObjectProtocol?
    init(store: DownloadStore) {
        self.store = store
        language = store.preferences.language
        observer = NotificationCenter.default.addObserver(forName: DownloadStore.dockPolicyChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, let store = self.store else { return }
            if self.language != store.preferences.language { self.language = store.preferences.language }
        }
    }
}

@main struct AkintiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Bilerek @StateObject değil: App gövdesi indirme değişikliklerinde yeniden çalışmasın.
    private let store: DownloadStore
    @StateObject private var chrome: AppChrome

    /// Geliştirici seçenekleri (Terminal'den):
    ///   --state-dir <klasör>  geçmiş/ayarlar için ayrı bir klasör kullanır (gerçek verilere dokunmadan deneme)
    ///   --add <bağlantı>      açılışta indirme ekler (birden çok kez verilebilir)
    ///   --select-first        açılışta ilk indirilen (yoksa ilk) satırı seçer
    ///   --open-settings       açılışta Ayarlar penceresini açar
    ///   --show-about          açılışta "Akıntı Hakkında" penceresini açar
    ///   --debug-install-update <zip> <sürüm>  güncelleyiciyi yerel bir paketle dener (uygulamanın kendisini değiştirir)
    init() {
        let args = CommandLine.arguments
        let stateDir = args.firstIndex(of: "--state-dir").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1], isDirectory: true) : nil }
        let store = DownloadStore(directory: stateDir)
        for (i, arg) in args.enumerated() where arg == "--add" && i + 1 < args.count { _ = store.add(args[i + 1]) }
        AppDelegate.store = store
        self.store = store
        _chrome = StateObject(wrappedValue: AppChrome(store: store))
    }
    // Not: Gövde bilerek sade tutulur. Her pencerenin içeriği ve menü komutları ayrı türlerdedir;
    // aksi halde SwiftUI'nin iç içe tür bilgisi çok derinleşip açılışta yığın taşmasına yol açabiliyor.
    var body: some Scene {
        WindowGroup(id: "main") { Themed(store: store) { ContentView(store: store) } }
            .defaultSize(width: 1120, height: 700)
            .windowToolbarStyle(.unified(showsTitle: true))
            .commands { AkintiCommands(store: store, language: chrome.language) }
        // IDM tarzı indirme penceresi (her indirme için bir tane).
        WindowGroup(id: "download", for: UUID.self) { $id in Themed(store: store) { DownloadPopup(store: store, id: id) } }
            .windowResizability(.contentSize)
            .defaultPosition(.topTrailing)
        Settings { Themed(store: store) { PreferencesView(store: store) } }
    }
}

/// Dil, yerel ayar ve tema: dil değişince içerik yeniden çizilir.
struct Themed<Content: View>: View {
    @ObservedObject var store: DownloadStore
    var appliesColorScheme = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .id(store.preferences.language)
            .environment(\.locale, L10n.locale)
            .preferredColorScheme(appliesColorScheme ? store.preferences.colorScheme : nil)
    }
}

/// Menü çubuğundaki Dosya, İndirmeler ve Yardım komutları.
struct AkintiCommands: Commands {
    let store: DownloadStore
    /// Dil değişince menü başlıkları yenilensin diye (store izlenmez).
    let language: String
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(t("Akıntı Hakkında", "About Akıntı")) { AboutPanel.show() }
        }
        CommandGroup(replacing: .newItem) {
            Button(t("Bağlantı ekle…", "Add Link…")) { store.isAdding = true }.keyboardShortcut("n")
            Button(t("Torrent dosyası aç…", "Open Torrent File…")) { TorrentFilePicker.choose(for: store) }.keyboardShortcut("o")
        }
        CommandMenu(t("İndirmeler", "Downloads")) {
            Button(t("Tümünü başlat", "Start All")) { store.resumeAll() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button(t("Tümünü duraklat", "Pause All")) { store.pauseAll() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button(t("Tamamlananları listeden temizle", "Clear Completed")) { store.clearCompleted() }
        }
        CommandGroup(replacing: .help) {
            Button(t("Akıntı nasıl kullanılır?", "How to Use Akıntı")) { store.isShowingHelp = true }
        }
    }
}

