import Foundation
import AppKit
import Security

/// Akıntı'nın kendini güncellemesi: GitHub'daki son sürümü denetler, indirir, SHA-256 ile doğrular,
/// uygulamayı kapatıp yeni sürümle değiştirir ve yeniden açar.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        var version: String
        var notes: String
        var pageURL: URL
        var zipURL: URL
        /// "sha256:<onaltılık>" (GitHub API) ya da yalnızca onaltılık özet.
        var sha256: String?
        var sha256FileURL: URL?
    }

    enum Phase: Equatable {
        case idle, checking, upToDate, available(Release), downloading(Double), installing, restarting, failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Yeni sürüm bulununca ana pencerede soru gösterilsin mi (otomatik denetimde true).
    @Published var promptVisible = false

    var latestAPI = URL(string: "https://api.github.com/repos/future01software/akinti/releases/latest")!
    static let bundleID = "org.akinti.downloads"
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }

    /// Karşılaştırmada kullanılan yüklü sürüm (testlerde değiştirilir).
    var installedVersion = Updater.currentVersion

    var available: Release? { if case .available(let r) = phase { return r } else { return nil } }
    var isBusyInstalling: Bool { if case .downloading = phase { return true }; return phase == .installing }

    // MARK: Denetim

    /// Günde en fazla bir kez (otomatik) ya da istendiğinde denetler. Yeni sürüm varsa `phase = .available`.
    func check(userInitiated: Bool) async {
        if case .downloading = phase { return }
        if phase == .installing { return }
        let key = "akinti.update.lastCheck"
        if !userInitiated, let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 24 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: key)
        phase = .checking
        do {
            var request = URLRequest(url: latestAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.network("HTTP \(http.statusCode)") }
            guard let release = Self.parseRelease(data) else { throw UpdateError.badRelease }
            if Self.isNewer(release.version, than: installedVersion) {
                phase = .available(release)
                if !userInitiated { promptVisible = true }
            } else {
                phase = .upToDate
            }
        } catch {
            phase = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    nonisolated static func parseRelease(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { $0["name"] as? String == "Akinti-macOS.zip" }),
              let zipURL = (zip["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let shaFile = assets.first { $0["name"] as? String == "Akinti-macOS.zip.sha256" }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: json["body"] as? String ?? "",
                       pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)) ?? zipURL,
                       zipURL: zipURL,
                       sha256: zip["digest"] as? String,
                       sha256FileURL: (shaFile?["browser_download_url"] as? String).flatMap(URL.init(string:)))
    }

    /// "0.10.3" < "0.11.0"; "-dev" gibi ekler göz ardı edilir.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? [] }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Uygulamayı güncelleme için kapatır. Betik, uygulama kapanınca eski sürümü yenisiyle değiştirip yeniden açar.
    ///
    /// Önceden doğrudan `NSApp.terminate` çağrılıyordu; ilerleme penceresi (sheet) açıkken SwiftUI kapanmayı
    /// iptal ediyor, uygulama açık kalıyordu. Artık önce ilerleme penceresi kapanır (phase = .restarting),
    /// sonra uygulama kapanır; yine kapanmazsa indirmelerin durumu kaydedilip süreç sonlandırılır.
    static func quitForUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            for window in NSApp.windows { window.attachedSheet.map { window.endSheet($0) } }
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            AppDelegate.store?.prepareForQuit()
            exit(0)
        }
    }

    /// Güncelleme dosyalarının (zip, açılan paket, betik) konduğu klasör. Testler her biri için ayrı klasör verir;
    /// paralel çalışan testler ortak geçici klasörde birbirinin dosyalarını saymasın.
    nonisolated(unsafe) static var workFolder = FileManager.default.temporaryDirectory

    // MARK: Temizlik

    /// Önceki güncellemelerden ve bileşen kurulumlarından kalan geçici dosyaları siler (açılışta çağrılır).
    nonisolated static func removeLeftovers(in folder: URL = FileManager.default.temporaryDirectory) {
        let prefixes = ["akinti-update-", "akinti-yt-dlp-", "akinti-ffmpeg-"]
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let lsregister = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        for name in items where prefixes.contains(where: name.hasPrefix) {
            let item = folder.appendingPathComponent(name)
            // İçinde uygulama varsa önce macOS'un uygulama kaydından çıkar (Spotlight / "Birlikte Aç" listesinde görünmesin).
            let app = item.appendingPathComponent("Akıntı.app")
            if FileManager.default.fileExists(atPath: app.path), FileManager.default.isExecutableFile(atPath: lsregister.path) {
                let p = Process(); p.executableURL = lsregister; p.arguments = ["-u", app.path]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try? p.run(); p.waitUntilExit()
            }
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: Kurulum

    enum UpdateError: LocalizedError {
        case network(String), badRelease, checksum, badBundle(String), notWritable
        var errorDescription: String? {
            switch self {
            case .network(let m): return t("Güncelleme sunucusuna ulaşılamadı: ", "Couldn't reach the update server: ") + m
            case .badRelease: return t("Sürüm bilgisi okunamadı.", "Couldn't read the release information.")
            case .checksum: return t("İndirilen güncelleme doğrulanamadı (SHA-256); kurulmadı.", "The downloaded update failed verification (SHA-256); not installed.")
            case .badBundle(let m): return t("İndirilen paket geçersiz: ", "The downloaded package is invalid: ") + m
            case .notWritable: return t("Akıntı’nın bulunduğu klasöre yazılamıyor; güncellemeyi sürüm sayfasından indirin.", "Can't write to Akıntı’s folder; download the update from the release page.")
            }
        }
    }

    /// İndirir, doğrular ve kurar. Başarılı olursa uygulama kapanır ve yeni sürüm açılır.
    /// `relaunch: false` yalnızca testler içindir: betik bu sürecin kapanmasını beklemez ve uygulamayı açmaz.
    func install(_ release: Release, appURL: URL = Bundle.main.bundleURL, relaunch: Bool = true) async {
        promptVisible = false
        do {
            guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else { throw UpdateError.notWritable }
            phase = .downloading(0)
            let zip = try await download(release.zipURL)
            defer { try? FileManager.default.removeItem(at: zip) }
            guard let expected = try await expectedSHA256(release) else { throw UpdateError.checksum }
            guard try ToolManager.sha256(of: zip) == expected else { throw UpdateError.checksum }
            phase = .installing
            let newApp = try Self.unpackAndValidate(zip, expectedVersion: release.version)
            do {
                let script = try Self.writeInstallScript(newApp: newApp, target: appURL, pid: relaunch ? ProcessInfo.processInfo.processIdentifier : 0, relaunch: relaunch)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [script.path]
                try process.run()
            } catch {
                try? FileManager.default.removeItem(at: newApp.deletingLastPathComponent())
                throw error
            }
            if relaunch { Self.quitForUpdate() ; phase = .restarting }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func expectedSHA256(_ release: Release) async throws -> String? {
        if let digest = release.sha256?.lowercased() {
            return digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
        }
        if let file = release.sha256FileURL {
            let (data, _) = try await URLSession.shared.data(from: file)
            return String(decoding: data, as: UTF8.self).split(separator: " ").first.map { String($0).lowercased() }
        }
        return nil
    }

    private func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                observation?.invalidate()
                if let error { return continuation.resume(throwing: UpdateError.network(error.localizedDescription)) }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return continuation.resume(throwing: UpdateError.network("HTTP \(http.statusCode)"))
                }
                guard let location else { return continuation.resume(throwing: UpdateError.network("?")) }
                let out = Self.workFolder.appendingPathComponent("akinti-update-\(UUID().uuidString).zip")
                do { try FileManager.default.moveItem(at: location, to: out); continuation.resume(returning: out) }
                catch { continuation.resume(throwing: UpdateError.network(error.localizedDescription)) }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let f = p.fractionCompleted
                Task { @MainActor in if case .downloading = self?.phase { self?.phase = .downloading(f) } }
            }
            task.resume()
        }
    }

    /// Zip'i açar; içinde aynı kimlikli, beklenen sürümde ve imzası bozulmamış Akıntı.app olmalı.
    nonisolated static func unpackAndValidate(_ zip: URL, expectedVersion: String) throws -> URL {
        let folder = Self.workFolder.appendingPathComponent("akinti-update-\(UUID().uuidString)")
        // Doğrulama başarısız olursa açılan paket geride kalmasın (Spotlight/Launchpad'de fazladan "Akıntı" görünüyordu).
        do { return try unpack(zip, into: folder, expectedVersion: expectedVersion) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    private nonisolated static func unpack(_ zip: URL, into folder: URL, expectedVersion: String) throws -> URL {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run(); ditto.waitUntilExit()
        guard ditto.terminationStatus == 0,
              let app = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app) else { throw UpdateError.badBundle(t("uygulama bulunamadı", "no app inside")) }
        guard bundle.bundleIdentifier == bundleID else { throw UpdateError.badBundle(t("farklı uygulama kimliği", "different bundle identifier")) }
        guard (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == expectedVersion else {
            throw UpdateError.badBundle(t("sürüm uyuşmuyor", "version mismatch"))
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), nil) == errSecSuccess else {
            throw UpdateError.badBundle(t("kod imzası bozuk", "broken code signature"))
        }
        return app
    }

    /// Uygulama kapanınca çalışan değiştirme betiği: eski sürümü yedekler, yenisini koyar, hata olursa geri alır.
    nonisolated static func writeInstallScript(newApp: URL, target: URL, pid: Int32, relaunch: Bool) throws -> URL {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let backup = target.deletingLastPathComponent().appendingPathComponent(".Akinti-eski-\(UUID().uuidString).app")
        let script = """
        #!/bin/sh
        # Akıntı güncelleyicisi: uygulama kapanana kadar bekler (en fazla 30 sn), sonra değiştirir.
        i=0; while [ \(pid) -gt 0 ] && kill -0 \(pid) 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
        # Hâlâ açıksa kapat: yeni sürüm çalışan bir uygulamanın altına konmaz.
        if [ \(pid) -gt 0 ] && kill -0 \(pid) 2>/dev/null; then
          kill -TERM \(pid) 2>/dev/null; j=0; while kill -0 \(pid) 2>/dev/null && [ $j -lt 25 ]; do sleep 0.2; j=$((j+1)); done
          kill -0 \(pid) 2>/dev/null && kill -KILL \(pid) 2>/dev/null; sleep 0.5
        fi
        if mv \(q(target.path)) \(q(backup.path)); then
          if mv \(q(newApp.path)) \(q(target.path)); then rm -rf \(q(backup.path)); else mv \(q(backup.path)) \(q(target.path)); fi
        fi
        xattr -dr com.apple.quarantine \(q(target.path)) 2>/dev/null
        # Geçici klasör ve bu betik silinir (geride Spotlight'ta görünen kopya kalmasın).
        rm -rf \(q(newApp.deletingLastPathComponent().path))
        \(relaunch ? "open \(q(target.path))" : ":")
        rm -f "$0"
        """
        let url = Self.workFolder.appendingPathComponent("akinti-update-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

import SwiftUI

/// Güncelleme indirilip kurulurken gösterilen küçük pencere.
struct UpdateProgressView: View {
    @ObservedObject var updater: Updater
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(t("Akıntı güncelleniyor", "Updating Akıntı"), systemImage: "arrow.down.circle").font(.headline)
            switch updater.phase {
            case .downloading(let f):
                ProgressView(value: f)
                Text(t("İndiriliyor… %\(Int(f * 100))", "Downloading… \(Int(f * 100))%")).font(.callout).foregroundStyle(.secondary)
            default:
                ProgressView()
                Text(t("Doğrulanıyor ve kuruluyor; Akıntı birazdan yeniden açılacak.", "Verifying and installing; Akıntı will reopen shortly.")).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(width: 360)
    }
}

/// Ayarlar → Güncellemeler
struct UpdateSettingsRows: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var store: DownloadStore

    var body: some View {
        LabeledContent(t("Yüklü sürüm", "Installed version")) {
            HStack(spacing: 10) {
                Text(Updater.currentVersion).foregroundStyle(.secondary)
                switch updater.phase {
                case .checking: ProgressView().controlSize(.small)
                case .downloading(let f): ProgressView(value: f).frame(width: 90)
                case .installing: ProgressView().controlSize(.small)
                case .available(let release):
                    Button(t("\(release.version) sürümüne güncelle", "Update to \(release.version)")) { Task { await updater.install(release) } }
                        .buttonStyle(.borderedProminent)
                default:
                    Button(t("Güncellemeleri denetle", "Check for Updates")) { Task { await updater.check(userInitiated: true) } }
                }
            }
        }
        switch updater.phase {
        case .upToDate: Label(t("Akıntı güncel.", "Akıntı is up to date."), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
        case .available(let release):
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Yeni sürüm: \(release.version)", "New version: \(release.version)")).font(.callout.weight(.semibold))
                Text(release.notes.replacingOccurrences(of: "### ", with: "").prefix(600)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button(t("Tüm sürüm notları", "Full release notes")) { NSWorkspace.shared.open(release.pageURL) }.buttonStyle(.link)
            }
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
        default: EmptyView()
        }
        Toggle(t("Güncellemeleri otomatik denetle (günde bir kez)", "Check for updates automatically (once a day)"), isOn: $store.preferences.autoCheckUpdates)
        Text(t("Güncelleme Akıntı’nın GitHub sürümlerinden indirilir ve SHA-256 ile doğrulanır; Akıntı kapanıp yeni sürümle açılır, indirmeler korunur.",
               "Updates are downloaded from Akıntı’s GitHub releases and verified with SHA-256; Akıntı restarts with the new version and downloads are kept."))
            .font(.callout).foregroundStyle(.secondary)
    }
}
