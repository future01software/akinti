import SwiftUI
import AppKit

extension Preferences {
    var colorScheme: ColorScheme? {
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }
}

struct PreferencesView: View {
    @ObservedObject var store: DownloadStore
    @State private var showHelp = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @ObservedObject private var tools = ToolManager.shared

    private var aria2Status: String {
        guard let url = TorrentEngine.executable else { return t("Bulunamadı", "Not found") }
        if url.path.contains("/Contents/Helpers/") { return t("Uygulamayla birlikte geliyor", "Included with the app") }
        return t("Homebrew: ", "Homebrew: ") + url.path
    }

    /// chrome://extensions sayfasını Chrome'da (yoksa Brave/Edge/Arc'ta) açar; hiçbiri yoksa adresi panoya kopyalar.
    private func openChromeExtensions() {
        let candidates = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "org.chromium.Chromium"]
        if let app = candidates.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first,
           let url = URL(string: "chrome://extensions") {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("chrome://extensions", forType: .string)
        }
    }

    private func openLicenses() {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Licenses")
        if FileManager.default.fileExists(atPath: bundled.path) { NSWorkspace.shared.open(bundled) }
        else { NSWorkspace.shared.open(URL(string: "https://github.com/future01software/akinti/tree/main/Licenses")!) }
    }
    var body: some View {
        Form {
            Section(t("Dil", "Language")) {
                Picker(t("Uygulama dili", "App language"), selection: $store.preferences.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                Text(t("Değişiklik hemen uygulanır. Sistem seçeneği Mac’in diline uyar.", "Changes apply immediately. System follows your Mac’s language."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(t("İndirilen dosyalar", "Downloaded files")) {
                LabeledContent(t("Kaydetme klasörü", "Save folder")) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(store.destinationFolder.path).font(.callout).textSelection(.enabled).multilineTextAlignment(.trailing)
                        Button(t("Klasör seç…", "Choose Folder…")) { FolderPicker.choose(for: store) }
                    }
                }
                Text(t("Yeni eklenen indirmeler bu klasöre kaydedilir. Mevcut indirmeler önceki klasörlerini kullanır.", "New downloads are saved here. Existing downloads keep their original folder."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(t("İndirme davranışı", "Download behavior")) {
                Picker(t("Aynı anda indirilecek dosya", "Simultaneous downloads"), selection: $store.limit) {
                    ForEach(1...8, id: \.self) { Text(t("\($0) dosya", "\($0) files")).tag($0) }
                }
                Text(t("Diğer dosyalar sırada bekler. Sayıyı azaltmak, başlamış indirmeleri durdurmaz.", "Other files wait in the queue. Lowering the number doesn’t stop running downloads."))
                    .font(.callout).foregroundStyle(.secondary)
                Picker(t("Dosya başına bağlantı", "Connections per file"), selection: $store.preferences.connectionsPerDownload) {
                    ForEach([1, 2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
                }
                Text(t("Sunucu destekliyorsa dosya parçalara bölünür ve aynı anda indirilir; desteklemiyorsa tek bağlantı kullanılır. Video sitelerinde parça sayısı olarak uygulanır.",
                       "If the server supports it, the file is split into parts downloaded at once; otherwise a single connection is used. On video sites it sets the number of fragments."))
                    .font(.callout).foregroundStyle(.secondary)
                Picker(t("Hız sınırı", "Speed limit"), selection: $store.preferences.speedLimitKB) {
                    ForEach(SpeedLimit.options, id: \.self) { Text(SpeedLimit.title($0)).tag($0) }
                }
                Text(t("Tüm indirmelerin toplam hızını sınırlar; alt çubuktan da değiştirilebilir. Video indirmelerinde yeni başlayanlara uygulanır.",
                       "Limits the combined speed of all downloads; also available in the status bar. For videos it applies to newly started downloads."))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(t("İndirme başlayınca ilerleme penceresini göster", "Show the progress window when a download starts"), isOn: $store.preferences.showProgressWindow)
                Text(t("IDM’deki gibi küçük bir pencere hız, kalan süre ve bağlantıları gösterir; indirme bitince dosyayı açmayı önerir. Bir seferde 3’ten fazla indirme eklenirse açılmaz.",
                       "Like IDM, a small window shows speed, time left and connections, and offers to open the file when it finishes. It doesn’t open when more than 3 downloads are added at once."))
                    .font(.callout).foregroundStyle(.secondary)
                Picker(t("Otomatik yeniden deneme", "Automatic retry"), selection: $store.preferences.retryLimit) {
                    Text(t("Kapalı", "Off")).tag(0)
                    ForEach(1...5, id: \.self) { Text(t("En fazla \($0) kez", "Up to \($0) times")).tag($0) }
                }
                Text(t("Geçici ağ ve sunucu hatalarında bekleyerek tekrar dener. Bulunamayan dosyalar (404) yeniden denenmez.", "Retries temporary network and server errors after a pause. Missing files (404) are not retried."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Torrent") {
                Toggle(t("İndirme bitince paylaşmaya devam et", "Keep seeding after the download finishes"), isOn: $store.preferences.torrentSeeding)
                Text(t("Açıksa, indirdiğiniz kadarını paylaşana kadar (oran 1.0) yükleme yapılır; kapalıysa indirme bitince durur. Torrent ve magnet bağlantıları aria2 ile indirilir" + (TorrentEngine.executable == nil ? " (kurulu değil: \(TorrentEngine.installCommand))." : "."),
                       "When on, Akıntı uploads until it has shared as much as it downloaded (ratio 1.0); when off it stops when done. Torrents and magnet links use aria2" + (TorrentEngine.executable == nil ? " (not installed: \(TorrentEngine.installCommand))." : ".")))
                    .font(.callout).foregroundStyle(.secondary)
                Text(t("Yalnızca paylaşım hakkı olan içerikleri (ör. Linux kalıpları, açık lisanslı dosyalar) indirin.", "Only download content you have the right to share (e.g. Linux images, openly licensed files)."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(t("Güncellemeler", "Updates")) {
                UpdateSettingsRows(store: store)
            }
            Section(t("Tarayıcı eklentisi", "Browser extension")) {
                Text(t("Chrome, Brave, Edge, Arc ve diğer Chromium tarayıcılarında sağ tıkla “Akıntı ile indir”, araç çubuğundan “Bu videoyu indir” ve IDM gibi indirme yakalama.",
                       "Right-click “Download with Akıntı”, “Download this video” from the toolbar, and IDM-style download capture in Chrome, Brave, Edge, Arc and other Chromium browsers."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(BrowserBridge.installedBrowsers) { browser in
                    LabeledContent(browser.name) {
                        Label(BrowserBridge.isRegistered(browser) ? t("Bağlantı hazır", "Connection ready") : t("Hazır değil", "Not ready"),
                              systemImage: BrowserBridge.isRegistered(browser) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(BrowserBridge.isRegistered(browser) ? Color.green : Color.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Kurulum", "Setup")).font(.callout.weight(.semibold))
                    Text(t("1. “Eklentiyi hazırla”ya basın: eklenti Belgeler → Akıntı Eklentisi klasörüne konur.\n2. Tarayıcıda chrome://extensions adresini açıp sağ üstten Geliştirici modunu açın.\n3. “Paketlenmemiş öğe yükle”ye basın, soldan Belgeler’i, sonra “Akıntı Eklentisi” klasörünü seçip “Seç”e basın.\nKlasörü silmeyin; Akıntı güncellendikçe eklenti de kendiliğinden güncellenir.",
                           "1. Click “Prepare extension”: it is placed in Documents → Akıntı Eklentisi.\n2. In your browser open chrome://extensions and turn on Developer mode (top right).\n3. Click “Load unpacked”, pick Documents on the left, then the “Akıntı Eklentisi” folder, and click “Select”.\nKeep the folder; the extension updates itself whenever Akıntı updates."))
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(t("Eklentiyi hazırla", "Prepare extension")) { BrowserBridge.revealExtension() }.buttonStyle(.borderedProminent)
                    Button(t("Chrome’da eklentileri aç", "Open extensions in Chrome")) { openChromeExtensions() }
                }
            }
            Section(t("Bileşenler", "Components")) {
                ForEach(ManagedTool.allCases) { tool in ToolRow(tool: tool) }
                LabeledContent {
                    Text(aria2Status).foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("aria2")
                        Text(t("Torrent ve magnet", "Torrents and magnet links")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Toggle(t("yt-dlp’yi otomatik güncelle (günde bir kez denetler)", "Keep yt-dlp up to date (checks once a day)"), isOn: $store.preferences.autoUpdateTools)
                if let error = tools.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                }
                HStack {
                    Text(t("yt-dlp GitHub’daki resmi sürümünden indirilir ve SHA-256 ile doğrulanır; ffmpeg, geliştiricisinin Apple onaylı imzası denetlenerek kurulur. Homebrew’la kurulmuş araçlar da kullanılır.",
                           "yt-dlp is downloaded from its official GitHub release and verified with SHA-256; ffmpeg is installed only if its developer’s Apple-notarized signature checks out. Tools installed with Homebrew are used too."))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Lisanslar…", "Licenses…")) { openLicenses() }
                }
            }
            Section(t("Bağlantı yakalama", "Link capture")) {
                Toggle(t("Kopyalanan indirme bağlantılarını yakala", "Capture copied download links"), isOn: $store.preferences.clipboardCapture)
                Text(t("Bir dosya bağlantısını kopyalayıp Akıntı’ya geçtiğinizde ekleme penceresi kendiliğinden açılır. Bağlantıları pencereye sürükleyip bırakabilirsiniz de.", "When you copy a file link and switch to Akıntı, the add window opens automatically. You can also drag links into the window."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(t("Menü çubuğu ve başlangıç", "Menu bar and startup")) {
                Toggle(t("Menü çubuğunda Akıntı simgesini göster", "Show the Akıntı icon in the menu bar"), isOn: $store.preferences.showMenuBarIcon)
                Toggle(t("Pencere kapanınca yalnızca menü çubuğunda çalış", "Run only in the menu bar when the window is closed"), isOn: $store.preferences.menuBarOnly)
                    .disabled(!store.preferences.showMenuBarIcon)
                Toggle(t("Dock’tan çıkınca menü çubuğunda çalışmaya devam et", "Keep running in the menu bar when quit from the Dock"), isOn: $store.preferences.keepRunningOnDockQuit)
                    .disabled(!store.preferences.showMenuBarIcon)
                Toggle(t("Mac açılınca Akıntı’yı başlat", "Open Akıntı at login"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        if let error = LaunchAtLogin.set(on) { store.message = error }
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }))
                Text(t("Menü çubuğu simgesi anlık hızı gösterir; tıklayınca indirmeleri duraklatıp sürdürebilir, yeni bağlantı ekleyebilirsiniz. Dock’tan “Çık” denince Akıntı menü çubuğunda kalır ve indirmeler sürer; tamamen kapatmak için menü çubuğundaki “Akıntı’dan çık” ya da ⌘Q kullanın.",
                       "The menu bar icon shows the current speed; click it to pause or resume downloads or add a link. Quitting from the Dock keeps Akıntı in the menu bar with downloads running; to quit completely use “Quit Akıntı” in the menu bar panel or ⌘Q."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(t("Görünüm", "Appearance")) {
                Picker(t("Tema", "Theme"), selection: $store.preferences.appearance) {
                    Text(t("Sistem", "System")).tag("system")
                    Text(t("Açık", "Light")).tag("light")
                    Text(t("Koyu", "Dark")).tag("dark")
                }.pickerStyle(.segmented)
            }
            Section(t("Yardım", "Help")) {
                LabeledContent(t("Kullanım rehberi", "User guide")) {
                    Button { showHelp = true } label: { Label(t("Nasıl kullanılır?", "How to Use"), systemImage: "questionmark.circle") }
                }
                HStack {
                    Label(t("Ayarlar otomatik kaydedilir", "Settings are saved automatically"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    Spacer()
                    Text("Akıntı " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")).foregroundStyle(.secondary)
                }.font(.callout)
            }
        }.formStyle(.grouped).frame(width: 620, height: 880)
        .navigationTitle(t("Ayarlar", "Settings"))
        .sheet(isPresented: $showHelp) { QuickStartView() }
        .alert(t("Ayarlar", "Settings"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(t("Tamam", "OK")) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}

struct QuickStartView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(t("Akıntı nasıl kullanılır?", "How to use Akıntı"), systemImage: "arrow.down.circle").font(.title2.bold())
            step("1", t("Bağlantıyı ekle", "Add a link"),
                 t("İndirme bağlantısını kopyalayıp Akıntı’ya geçin; pencere kendiliğinden açılır. Ya da + düğmesine (⌘N) basın veya bağlantıyı pencereye sürükleyin.",
                   "Copy a download link and switch to Akıntı; the add window opens by itself. Or press + (⌘N), or drag the link into the window."))
            step("2", t("İndir veya zamanla", "Download or schedule"),
                 t("İndir’e basın; Sonra indir listeye duraklatılmış ekler, Belirli saatte başlat ise planlar. Zamanlama için Akıntı açık ve Mac uyanık olmalıdır.",
                   "Press Download. Download Later adds it paused; Start at a specific time schedules it. Akıntı must be open and the Mac awake for schedules."))
            step("3", t("Yönet ve dosyanı bul", "Manage and find your file"),
                 t("Soldaki kategoriler dosyaları türüne göre ayırır. Satırları seçip araç çubuğundan devam ettirin veya duraklatın; sağ tık daha fazla seçenek sunar. Tamamlanan dosyayı açmak için çift tıklayın.",
                   "Categories on the left group files by type. Select rows and resume or pause them from the toolbar; right-click for more. Double-click a finished file to open it."))
            Divider()
            Text(t("Ayarlar: araç çubuğundaki dişli veya ⌘, kısayolu. Bu rehber Yardım menüsünde de bulunur.", "Settings: the gear in the toolbar or ⌘,. This guide is also in the Help menu.")).font(.callout)
            Text(t("Video siteleri (YouTube, Vimeo ve yüzlercesi) için yt-dlp gerekir: Terminal’de brew install yt-dlp ffmpeg. Video indirirken kalite seçebilir veya yalnızca sesi alabilirsiniz. Tarayıcı uzantısı henüz yoktur.",
                   "Video sites (YouTube, Vimeo and hundreds more) need yt-dlp: run brew install yt-dlp ffmpeg in Terminal. You can choose the quality or keep only the audio. A browser extension is not available yet."))
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button(t("Anladım", "Got It")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 580)
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).frame(width: 30, height: 30).background(.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Ayarlar → Bileşenler: bir aracın durumu ve Kur/Güncelle düğmesi.
struct ToolRow: View {
    let tool: ManagedTool
    @ObservedObject private var tools = ToolManager.shared

    private var status: String {
        if let version = ToolManager.installedVersion(tool), ToolManager.installedURL(tool) != nil { return t("Kurulu · ", "Installed · ") + version }
        if let url = VideoEngine.find(tool.fileName) { return "Homebrew: " + url.deletingLastPathComponent().path }
        return t("Kurulu değil", "Not installed")
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(status).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if tools.isInstalling(tool) {
                    ProgressView(value: tools.progress[tool] ?? 0).frame(width: 90)
                } else if ToolManager.installedURL(tool) != nil {
                    Button(t("Güncelle", "Update")) {
                        Task {
                            if tool == .ytdlp { await tools.updateYtDlpIfNeeded(force: true) } else { await tools.install(tool) }
                        }
                    }
                } else {
                    Button(t("Kur", "Install")) { Task { await tools.install(tool) } }.buttonStyle(.borderedProminent)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                Text(tool.purpose).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
