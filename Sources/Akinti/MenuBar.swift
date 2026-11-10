import SwiftUI
import AppKit
import ServiceManagement
import Combine

/// Ana pencereyi ve Ayarlar'ı açar; menü çubuğu kipindeyken Dock simgesini geri getirir.
/// SwiftUI'nin pencere açma eylemleri ana pencere ilk göründüğünde saklanır (menü çubuğu açılır penceresi bir
/// SwiftUI sahnesinin içinde olmadığı için bu eylemlere doğrudan erişemez).
@MainActor
enum MainWindow {
    static var openAction: OpenWindowAction?
    static var settingsAction: OpenSettingsAction?

    static func isMainWindow(_ window: NSWindow) -> Bool { window.identifier?.rawValue.hasPrefix("main") == true }
    static var existing: NSWindow? { NSApp.windows.first { isMainWindow($0) && $0.isVisible } }

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = existing { window.makeKeyAndOrderFront(nil) }
        else if let openAction { openAction(id: "main") }
        else { sendReopenToSelf() } // pencere hiç açılmadıysa (ör. girişte başlatıldı): Dock'a tıklamakla aynı
    }

    static func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsAction { settingsAction(); return }
        // Yedek: uygulama menüsündeki "Ayarlar…" (⌘,) öğesini çalıştır.
        if let menu = NSApp.mainMenu?.items.first?.submenu, let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
            menu.performActionForItem(at: index)
        }
    }

    private static func sendReopenToSelf() {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier),
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        DispatchQueue.main.async { _ = try? event.sendEvent(options: [.noReply], timeout: 2) }
    }
}

/// Menü çubuğu simgesi ve açılır paneli (NSStatusItem + NSPopover).
///
/// SwiftUI'nin MenuBarExtra'sı yerine kullanılır: MenuBarExtra paneli ayrı bir pencere olarak açıyordu ve uygulama
/// yalnızca menü çubuğu kipindeyken (Dock simgesi gizliyken) Sahne Yöneticisi ile birlikte simge vurgulansa da
/// panel ekrana gelmiyordu. NSPopover doğrudan simgeye bağlıdır; Space'lerden ve Sahne Yöneticisi'nden etkilenmez.
@MainActor
final class StatusItemController: NSObject {
    private let store: DownloadStore
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(store: DownloadStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = true
        let panel = MenuBarPanel(store: store) { [weak self] in self?.popover.performClose(nil) }
        popover.contentViewController = NSHostingController(rootView: Themed(store: store, appliesColorScheme: false) { panel })
        // Simgedeki hız saniyede en fazla bir kez güncellenir.
        store.objectWillChange
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateButton() } }
            .store(in: &subscriptions)
        // Eklentiden bağlantı gelip ana pencere kapalıysa pencereyi aç.
        store.$mainWindowRequest.dropFirst().sink { _ in DispatchQueue.main.async { MainWindow.show() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: DownloadStore.dockPolicyChanged)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &subscriptions)
        updateVisibility()
    }

    func updateVisibility() {
        let visible = store.preferences.showMenuBarIcon
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "AkintiStatusItem" // Barbee/Bartender gibi düzenleyiciler yerini hatırlasın
            item.button?.target = self
            item.button?.action = #selector(toggle(_:))
            item.button?.imagePosition = .imageLeading
            self.item = item
            updateButton()
        } else if !visible, let item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func updateButton() {
        guard let button = item?.button else { return }
        let active = store.items.contains { $0.state == "İndiriliyor" }
        let image = NSImage(systemSymbolName: active ? "arrow.down.circle.fill" : "arrow.down.circle", accessibilityDescription: "Akıntı")
        image?.isTemplate = true
        button.image = image
        let title = active ? " " + Format.speed(store.totalSpeed) : ""
        if button.title != title {
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
        }
        button.toolTip = "Akıntı"
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(sender); return }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        // Açılır pencere klavye ve fareyi hemen alsın (menü çubuğu kipinde uygulama etkin değildir).
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}

/// Menü çubuğu simgesine tıklayınca açılan panel.
struct MenuBarPanel: View {
    @ObservedObject var store: DownloadStore
    /// Açılır pencereyi kapatır (bir işlemden sonra).
    var dismiss: () -> Void = {}
    @ObservedObject private var updater = Updater.shared

    private var visible: [Download] {
        let order = ["İndiriliyor": 0, "Duraklatılıyor": 1, "Bekliyor": 2, "Yeniden denenecek": 3, "Planlandı": 4, "Duraklatıldı": 5]
        return store.items.filter { order[$0.state] != nil }.sorted { order[$0.state]! < order[$1.state]! }
    }
    private var active: Int { store.items.filter { $0.state == "İndiriliyor" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down").font(.headline).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(active > 0 ? Color.accentColor : Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Akıntı").font(.headline)
                    Text(active > 0 ? t("\(active) aktif · \(Format.speed(store.totalSpeed))", "\(active) active · \(Format.speed(store.totalSpeed))") : t("Boşta", "Idle"))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button { dismiss(); MainWindow.show(); store.isAdding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help(t("Bağlantı ekle", "Add Link"))
            }

            Divider()

            if visible.isEmpty {
                Text(t("Aktif indirme yok", "No active downloads")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(visible.prefix(6)) { d in row(d) }
                }
                if visible.count > 6 {
                    Text(t("+\(visible.count - 6) daha", "+\(visible.count - 6) more")).font(.callout).foregroundStyle(.secondary)
                }
            }

            if let release = updater.available {
                Button { dismiss(); MainWindow.show(); Updater.shared.promptVisible = true } label: {
                    Label(t("Akıntı \(release.version) hazır — güncelle", "Akıntı \(release.version) is available — update"), systemImage: "arrow.down.app")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
            }

            Divider()

            HStack {
                Button(t("Tümünü başlat", "Start All")) { store.resumeAll() }.disabled(!store.items.contains { $0.canStart })
                Button(t("Tümünü duraklat", "Pause All")) { store.pauseAll() }.disabled(!store.items.contains { $0.canPause })
                Spacer()
                Menu {
                    Picker(t("Hız sınırı", "Speed limit"), selection: $store.preferences.speedLimitKB) {
                        ForEach(SpeedLimit.options, id: \.self) { Text(SpeedLimit.title($0)).tag($0) }
                    }.pickerStyle(.inline)
                } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                .menuStyle(.borderlessButton).fixedSize().help(t("Hız sınırı", "Speed limit"))
            }
            .controlSize(.small)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuButton(t("Akıntı’yı aç", "Open Akıntı"), "macwindow") { dismiss(); MainWindow.show() }
                menuButton(t("Ayarlar…", "Settings…"), "gearshape") { dismiss(); MainWindow.showSettings() }
                menuButton(t("Akıntı’dan çık", "Quit Akıntı"), "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func row(_ d: Download) -> some View {
        HStack(spacing: 8) {
            FileIcon(category: d.category, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name).lineLimit(1).truncationMode(.middle).font(.callout)
                ProgressView(value: d.progress).controlSize(.small)
                    .tint(StatusCell.color(d.state) == .secondary ? Color.accentColor : StatusCell.color(d.state))
                Text(d.state == "İndiriliyor"
                     ? [d.total > 0 ? Format.percent(d.progress) : Format.bytes(d.received), store.speeds[d.id].map(Format.speed), store.eta(for: d).map(Format.eta)].compactMap { $0 }.joined(separator: " · ")
                     : L10n.state(d.state))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if d.canStart {
                Button { store.start(d.id) } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless).help(t("Devam et", "Resume"))
            } else if d.canPause {
                Button { store.pause(d.id) } label: { Image(systemName: "pause.fill") }.buttonStyle(.borderless).help(t("Duraklat", "Pause"))
            }
        }
    }

    private func menuButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).padding(.vertical, 3)
    }

}

/// Mac açılınca Akıntı'yı başlatma (macOS Giriş Öğeleri).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    /// Hata olursa açıklamasını döndürür.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return t("Giriş öğesi ayarlanamadı: ", "Could not change the login item: ") + error.localizedDescription
        }
    }
}
