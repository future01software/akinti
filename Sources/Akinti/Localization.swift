import Foundation

/// Uygulama dili. "system" Mac'in diline uyar: Türkçe ise Türkçe, değilse İngilizce.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return t("Sistem", "System")
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }
}

enum L10n {
    /// Ayarlardaki seçim; DownloadStore tarafından güncellenir.
    static var preference = "system"
    static var isEnglish: Bool {
        switch preference {
        case "en": return true
        case "tr": return false
        default: return !(Locale.preferredLanguages.first ?? "tr").lowercased().hasPrefix("tr")
        }
    }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "tr_TR") }

    /// İç durum anahtarları Türkçe saklanır (geçmiş dosyasıyla uyumluluk için); ekranda çevrilir.
    static func state(_ s: String) -> String {
        guard isEnglish else { return s }
        switch s {
        case "Bekliyor": return "Queued"
        case "İndiriliyor": return "Downloading"
        case "Duraklatılıyor": return "Pausing"
        case "Duraklatıldı": return "Paused"
        case "Planlandı": return "Scheduled"
        case "Yeniden denenecek": return "Retrying"
        case "Tamamlandı": return "Completed"
        case "Hata": return "Error"
        default: return s
        }
    }
}

/// Türkçe ve İngilizce metinden geçerli dile uygun olanı döndürür.
func t(_ tr: String, _ en: String) -> String { L10n.isEnglish ? en : tr }
