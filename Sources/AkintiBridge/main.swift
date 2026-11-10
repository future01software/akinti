// Akıntı tarayıcı köprüsü (Native Messaging host).
// Chrome/Brave/Edge/Arc eklentisi bu programı başlatır ve stdin/stdout üzerinden JSON mesajlar gönderir:
//   {"type":"ping"}                                   -> {"ok":true,"version":"0.10.0"}
//   {"type":"add","urls":[...],"referrer":"...","userAgent":"...","mode":"video"}
//                                                     -> {"ok":true}  (Akıntı'nın ekleme penceresi açılır)
// Köprü yalnızca bağlantıları Akıntı'ya iletir; dosya indirmez, kendi başına bir şey çalıştırmaz.
import Foundation
import AppKit
import AkintiShared

let stdin = FileHandle.standardInput
let stdout = FileHandle.standardOutput

/// Köprü, Akıntı.app/Contents/Helpers içinde çalışır; uygulamanın sürümü oradan okunur.
let appBundle = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let version = Bundle(url: appBundle)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

func reply(_ object: [String: Any]) {
    guard let data = try? NativeMessage.encode(object) else { return }
    stdout.write(data)
}

func open(_ link: AkintiLink) -> Bool {
    guard let url = link.url else { return false }
    // Testlerde Akıntı'yı açmadan bağlantıyı yazdırır.
    if ProcessInfo.processInfo.environment["AKINTI_BRIDGE_DRYRUN"] != nil {
        FileHandle.standardError.write(Data((url.absoluteString + "\n").utf8))
        return true
    }
    // Akıntı'nın bu kopyası açılır (ör. Programlar'daki); kapalıysa başlatılır.
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let done = DispatchSemaphore(value: 0)
    var ok = false
    if FileManager.default.fileExists(atPath: appBundle.appendingPathComponent("Contents/Info.plist").path) {
        NSWorkspace.shared.open([url], withApplicationAt: appBundle, configuration: configuration) { _, error in ok = error == nil; done.signal() }
    } else {
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in ok = error == nil; done.signal() }
    }
    _ = done.wait(timeout: .now() + 10)
    return ok
}

while let message = (try? NativeMessage.read(from: stdin)) ?? nil {
    switch message["type"] as? String {
    case "ping":
        reply(["ok": true, "version": version])
    case "add":
        let urls = (message["urls"] as? [String] ?? []).compactMap(URL.init(string:)).filter(AkintiLink.isAllowed)
        guard !urls.isEmpty else { reply(["ok": false, "error": "no-valid-urls"]); continue }
        let link = AkintiLink(urls: urls, referrer: message["referrer"] as? String,
                              userAgent: message["userAgent"] as? String, mode: message["mode"] as? String)
        reply(open(link) ? ["ok": true] : ["ok": false, "error": "open-failed"])
    default:
        reply(["ok": false, "error": "unknown-type"])
    }
}
