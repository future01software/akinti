import AppKit

/// "Akıntı Hakkında" penceresi: macOS'un standart penceresine tanıtım, bağlantılar ve lisans bilgisi eklenir.
@MainActor
enum AboutPanel {
    static let repository = "https://github.com/future01software/akinti"

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        // .version boş: "Sürüm 1.0.1 (1.0.1)" yerine yalnızca "Sürüm 1.0.1" yazar.
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits(), .version: ""])
    }

    static func credits() -> NSAttributedString {
        let version = Updater.currentVersion
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 5
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: center,
        ]
        let strong: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: center,
        ]
        func link(_ title: String, _ url: String) -> NSAttributedString {
            var attributes = body
            attributes[.link] = URL(string: url)
            return NSAttributedString(string: title, attributes: attributes)
        }
        let text = NSMutableAttributedString()
        func add(_ string: String, _ attributes: [NSAttributedString.Key: Any]) { text.append(NSAttributedString(string: string, attributes: attributes)) }
        let dot = NSAttributedString(string: "  ·  ", attributes: body)
        add(t("Mac için ücretsiz, açık kaynak indirme yöneticisi", "A free, open-source download manager for the Mac") + "\n", strong)
        add(t("Çok bağlantılı indirme · Video siteleri · Torrent · Chrome eklentisi", "Multi-connection downloads · Video sites · Torrents · Chrome extension") + "\n", body)
        text.append(link("GitHub", repository)); text.append(dot)
        text.append(link(t("Sürüm notları", "Release notes"), "\(repository)/releases/tag/v\(version)")); text.append(dot)
        text.append(link(t("Hata bildir", "Report a bug"), "\(repository)/issues/new")); text.append(dot)
        text.append(link(t("Lisanslar", "Licenses"), "\(repository)/blob/main/Licenses/THIRD-PARTY.md"))
        add("\n" + t("aria2, yt-dlp ve FFmpeg ile · Reklam yok, veri toplamaz", "Built with aria2, yt-dlp and FFmpeg · No ads, no tracking"), body)
        return text
    }
}
