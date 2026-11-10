import SwiftUI
import AppKit
import ServiceManagement

/// Ana pencereyi bulur, yoksa açar; uygulamayı öne getirir. Menü çubuğu kipindeyken Dock simgesini geri getirir.
enum MainWindow {
    static func isMainWindow(_ window: NSWindow) -> Bool { window.identifier?.rawValue.hasPrefix("main") == true }
    static var existing: NSWindow? { NSApp.windows.first { isMainWindow($0) && $0.isVisible } }

    static func show(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        if let window = existing { window.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Menü çubuğundaki simge: indirme varken yanında toplam hız yazar.
struct MenuBarLabel: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.openWindow) private var openWindow
    private var active: Int { store.items.filter { $0.state == "İndiriliyor" }.count }
    var body: some View {
        label
            // Ana pencere kapalıyken (ör. yalnızca menü çubuğu kipinde) eklentiden bağlantı gelirse pencereyi açar.
            .onChange(of: store.mainWindowRequest) { _, _ in MainWindow.show(openWindow: openWindow) }
    }
    @ViewBuilder private var label: some View {
        if active > 0 {
            Label(Format.speed(store.totalSpeed), systemImage: "arrow.down.circle.fill").labelStyle(.titleAndIcon).monospacedDigit()
        } else {
            Image(systemName: "arrow.down.circle")
        }
    }
}

/// Menü çubuğu simgesine tıklayınca açılan panel.
struct MenuBarPanel: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
                Button { open(); store.isAdding = true } label: { Image(systemName: "plus") }
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
                menuButton(t("Akıntı’yı aç", "Open Akıntı"), "macwindow") { open() }
                menuButton(t("Ayarlar…", "Settings…"), "gearshape") { NSApp.activate(ignoringOtherApps: true); openSettings() }
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

    private func open() { MainWindow.show(openWindow: openWindow) }
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
