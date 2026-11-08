import SwiftUI
import AppKit

/// IDM'deki "indirme durumu" penceresinin macOS karşılığı: indirme başlayınca açılır,
/// bitince "İndirme tamamlandı" ekranına dönüşür.
struct DownloadPopup: View {
    @ObservedObject var store: DownloadStore
    let id: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCancel = false

    private var item: Download? { store.items.first { $0.id == id } }

    var body: some View {
        Group {
            if let item {
                switch item.state {
                case "Tamamlandı": completed(item)
                case "Hata": failed(item)
                default: progress(item)
                }
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .frame(width: 480)
        // Bu pencereler macOS tarafından geri yüklenmez; indirmesi olmayan (silinmiş) pencere hemen kapanır.
        .background(WindowAccessor { window in
            window.isRestorable = false
            if item == nil { DispatchQueue.main.async { window.close() } }
        })
        .navigationTitle(item?.name ?? "Akıntı")
    }

    // MARK: İndiriliyor / duraklatıldı

    private func progress(_ d: Download) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(d, subtitle: d.isTorrent == true ? "BitTorrent · " + (TorrentEngine.isMagnet(d.source) ? "Magnet" : d.source.lastPathComponent) : d.source.host ?? d.source.absoluteString)
            VStack(alignment: .leading, spacing: 6) {
                if let map = d.pieceMap {
                    PieceBar(map: map, tint: tint(d))
                } else if let segments = d.segments, segments.count > 1 {
                    SegmentBar(segments: segments, tint: tint(d))
                } else {
                    ProgressView(value: d.progress).tint(tint(d))
                }
                HStack {
                    Text(d.total > 0 ? Format.percent(d.progress) : Format.bytes(d.received)).font(.title3.weight(.semibold).monospacedDigit())
                    Spacer()
                    Text(L10n.state(d.state)).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    stat(t("İndirilen", "Downloaded"), d.total > 0 ? "\(Format.bytes(d.received)) / \(Format.bytes(d.total))" : Format.bytes(d.received))
                    stat(t("Hız", "Speed"), store.speeds[d.id].map(Format.speed) ?? "—")
                }
                GridRow {
                    stat(t("Kalan süre", "Time left"), store.eta(for: d).map(Format.eta) ?? "—")
                    if d.isTorrent == true {
                        stat(t("Kaynak / Eş", "Seeds / Peers"), "\(d.seeders ?? 0) / \(d.peers ?? 0)")
                    } else {
                        stat(t("Bağlantı", "Connections"), d.segments.map { "\($0.filter { !$0.isDone }.count) / \($0.count)" } ?? (d.isVideo == true ? "yt-dlp" : "1"))
                    }
                }
            }
            Divider()
            HStack {
                Toggle(t("Bu pencereyi bir daha gösterme", "Don’t show this window again"), isOn: Binding(
                    get: { !store.preferences.showProgressWindow },
                    set: { store.preferences.showProgressWindow = !$0 }))
                    .toggleStyle(.checkbox).font(.callout)
                Spacer()
                Button(t("İptal", "Cancel"), role: .destructive) { confirmCancel = true }
                if d.canStart {
                    Button { store.start(d.id) } label: { Label(t("Devam et", "Resume"), systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { store.pause(d.id) } label: { Label(t("Duraklat", "Pause"), systemImage: "pause.fill") }
                        .disabled(!d.canPause)
                }
                Button(t("Gizle", "Hide")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .confirmationDialog(t("İndirme iptal edilsin mi?", "Cancel this download?"), isPresented: $confirmCancel) {
            Button(t("İndirmeyi iptal et", "Cancel Download"), role: .destructive) { store.remove(d.id); dismiss() }
        } message: { Text(t("Yarım kalan dosya silinir ve indirme listeden kaldırılır.", "The partial file is deleted and the download is removed from the list.")) }
    }

    // MARK: Tamamlandı

    private func completed(_ d: Download) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    FileIcon(category: d.category, size: 48)
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, .green).offset(x: 6, y: 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("İndirme tamamlandı", "Download complete")).font(.title3.weight(.semibold))
                    Text(d.name).lineLimit(1).truncationMode(.middle)
                    Text([Format.bytes(d.total), d.saved?.deletingLastPathComponent().lastPathComponent].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Spacer()
                if let saved = d.saved {
                    Button(t("Finder’da göster", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([saved]); dismiss() }
                    Button(t("Aç", "Open")) { NSWorkspace.shared.open(saved); dismiss() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
                Button(t("Kapat", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }

    // MARK: Hata

    private func failed(_ d: Download) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(d, subtitle: d.source.absoluteString)
            Label(d.error ?? t("İndirme başarısız oldu.", "The download failed."), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Spacer()
                Button(t("Kapat", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(t("Yeniden dene", "Try Again")) { store.start(d.id) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    // MARK: Parçalar

    private func header(_ d: Download, subtitle: String) -> some View {
        HStack(spacing: 12) {
            FileIcon(category: d.category, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }.font(.callout)
    }

    private func tint(_ d: Download) -> Color {
        StatusCell.color(d.state) == .secondary ? Color.accentColor : StatusCell.color(d.state)
    }
}

/// SwiftUI görünümünün bulunduğu NSWindow'a erişim (geri yükleme ayarı ve kapatma için).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { Probe(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Probe: NSView {
        let onWindow: (NSWindow) -> Void
        init(onWindow: @escaping (NSWindow) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
