import Foundation
import AppKit
import AkintiShared

/// Chrome ve Chromium tabanlı tarayıcılar için Native Messaging kaydı.
/// Akıntı açılınca, kurulu tarayıcıların `NativeMessagingHosts` klasörüne köprünün yolunu yazar;
/// böylece eklenti Akıntı ile açılır pencere çıkmadan konuşur.
enum BrowserBridge {
    /// Eklentinin sabit kimliği (Extension/chrome/manifest.json içindeki "key" alanından türetilir).
    /// Chrome Web Store'da yayımlanınca mağazanın verdiği kimlik de buraya eklenir.
    static let extensionIDs = ["ojpoadglbpcggeknbppjmhmeajdeiklk"]

    struct Browser: Identifiable {
        let name: String
        let dataFolder: String   // ~/Library/Application Support altında
        var id: String { name }
    }

    static let browsers = [
        Browser(name: "Google Chrome", dataFolder: "Google/Chrome"),
        Browser(name: "Google Chrome Beta", dataFolder: "Google/Chrome Beta"),
        Browser(name: "Chromium", dataFolder: "Chromium"),
        Browser(name: "Brave", dataFolder: "BraveSoftware/Brave-Browser"),
        Browser(name: "Microsoft Edge", dataFolder: "Microsoft Edge"),
        Browser(name: "Arc", dataFolder: "Arc/User Data"),
        Browser(name: "Vivaldi", dataFolder: "Vivaldi"),
    ]

    /// Testlerde değiştirilir.
    nonisolated(unsafe) static var applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// Uygulamanın içindeki köprü (Contents/Helpers/akinti-bridge). `swift run` ile çalışırken yoktur.
    static var bridgeExecutable: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/akinti-bridge")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func manifest(bridge: URL) -> [String: Any] {
        [
            "name": NativeMessage.hostName,
            "description": "Akıntı indirme yöneticisi köprüsü",
            "path": bridge.path,
            "type": "stdio",
            "allowed_origins": extensionIDs.map { "chrome-extension://\($0)/" },
        ]
    }

    static func manifestURL(for browser: Browser) -> URL {
        applicationSupport.appendingPathComponent(browser.dataFolder)
            .appendingPathComponent("NativeMessagingHosts/\(NativeMessage.hostName).json")
    }

    /// Yalnızca kurulu (veri klasörü olan) tarayıcılar.
    static var installedBrowsers: [Browser] {
        browsers.filter { FileManager.default.fileExists(atPath: applicationSupport.appendingPathComponent($0.dataFolder).path) }
    }

    static func isRegistered(_ browser: Browser) -> Bool { FileManager.default.fileExists(atPath: manifestURL(for: browser).path) }

    /// Kurulu tarayıcılara köprüyü kaydeder; uygulama taşınmışsa yolu günceller. Kaydedilen tarayıcı adlarını döndürür.
    @discardableResult
    static func register(bridge: URL? = bridgeExecutable) -> [String] {
        guard let bridge else { return [] }
        var done: [String] = []
        for browser in installedBrowsers {
            let url = manifestURL(for: browser)
            do {
                let data = try JSONSerialization.data(withJSONObject: manifest(bridge: bridge), options: [.prettyPrinted, .sortedKeys])
                if (try? Data(contentsOf: url)) != data {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                }
                done.append(browser.name)
            } catch { continue }
        }
        return done
    }

    /// Kullanıcının Chrome'da "Paketlenmemiş öğe yükle" ile seçtiği klasör. Gizli Kitaplık klasöründe olursa
    /// Chrome'un dosya seçicisinde görünmüyor; bu yüzden Belgeler'de durur. Testlerde değiştirilir.
    nonisolated(unsafe) static var extensionFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Akıntı Eklentisi", isDirectory: true)

    static var bundledExtension: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension") }

    /// Eklentiyi Belgeler/Akıntı Eklentisi klasörüne kopyalar (veya günceller) ve Finder'da gösterir.
    @discardableResult
    static func revealExtension() -> URL? {
        guard FileManager.default.fileExists(atPath: bundledExtension.path) else {
            NSWorkspace.shared.open(URL(string: "https://github.com/future01software/akinti/releases/latest")!)
            return nil
        }
        guard copyExtension(from: bundledExtension, to: extensionFolder) else { return nil }
        NSWorkspace.shared.activateFileViewerSelecting([extensionFolder.appendingPathComponent("manifest.json")])
        return extensionFolder
    }

    /// Kullanıcı eklentiyi kurduysa (klasör varsa) ve Akıntı'daki sürüm farklıysa klasörü günceller.
    /// Chrome yeni sürümü bir sonraki açılışta (veya eklentiler sayfasında "yeniden yükle" ile) kullanır.
    @discardableResult
    static func syncInstalledExtension(from source: URL = bundledExtension, to target: URL = extensionFolder) -> Bool {
        guard FileManager.default.fileExists(atPath: target.appendingPathComponent("manifest.json").path),
              let new = manifestVersion(source), new != manifestVersion(target) else { return false }
        return copyExtension(from: source, to: target)
    }

    static func manifestVersion(_ folder: URL) -> String? {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])?["version"] as? String
    }

    /// Klasörün içeriğini değiştirir; klasörün kendisi (Chrome'un hatırladığı yol) aynı kalır.
    private static func copyExtension(from source: URL, to target: URL) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(atPath: target.path) { try fm.removeItem(at: target.appendingPathComponent(item)) }
            for item in try fm.contentsOfDirectory(atPath: source.path) {
                try fm.copyItem(at: source.appendingPathComponent(item), to: target.appendingPathComponent(item))
            }
            return true
        } catch { return false }
    }
}
