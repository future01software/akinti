import Foundation

/// Torrent ve magnet indirmeleri için aria2 (https://aria2.github.io) arka plan servisi.
/// Akıntı, aria2c'yi yalnızca 127.0.0.1'den erişilebilen ve rastgele bir parola ile korunan
/// JSON-RPC sunucusu olarak başlatır. `--stop-with-process` sayesinde Akıntı kapanınca aria2 de kapanır.
final class TorrentEngine: @unchecked Sendable {
    static let installCommand = "brew install aria2"
    /// Testlerde farklı bir aria2c vermek için.
    static var overrideExecutable: URL?
    static var executable: URL? { overrideExecutable ?? VideoEngine.find("aria2c") }

    /// Testlerde DHT/LPD kapatılır ve dinleme portu sabitlenir.
    var extraArguments: [String] = []
    private(set) var isRunning = false
    private var process: Process?
    private var port = 0
    private let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let lock = NSLock()

    enum EngineError: LocalizedError {
        case missing, failed(String)
        var errorDescription: String? {
            switch self {
            case .missing: return t("Torrent için aria2 kurulu değil. Terminal’de şunu çalıştırın: ", "aria2 is required for torrents. Run this in Terminal: ") + TorrentEngine.installCommand
            case .failed(let message): return message
            }
        }
    }

    deinit { process?.terminate() }

    /// aria2 çalışmıyorsa başlatır. Seçenekler (paylaşım, hız sınırı) her çağrıda güncellenir.
    func start(seeding: Bool, speedLimit: Int64) async throws {
        if !isRunning {
            guard let exe = Self.executable else { throw EngineError.missing }
            var lastError = ""
            for _ in 0..<5 {
                let candidate = Int.random(in: 20000...60000)
                let p = Process()
                p.executableURL = exe
                p.arguments = ["--enable-rpc", "--rpc-listen-all=false", "--rpc-listen-port=\(candidate)", "--rpc-secret=\(secret)",
                               "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
                               "--continue=true", "--follow-torrent=mem", "--bt-save-metadata=false", "--file-allocation=none",
                               "--max-concurrent-downloads=16", "--console-log-level=error", "--summary-interval=0",
                               "--seed-time=0", "--bt-detach-seed-only=true"] + extraArguments
                p.environment = VideoEngine.environment
                let err = Pipe()
                p.standardOutput = FileHandle.nullDevice
                p.standardError = err
                try p.run()
                // RPC hazır olana kadar bekle (en fazla ~3 sn).
                port = candidate
                for _ in 0..<30 where p.isRunning {
                    if (try? await call("aria2.getVersion", [])) != nil { process = p; isRunning = true; break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if isRunning { break }
                p.terminate()
                lastError = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
            }
            guard isRunning else { throw EngineError.failed(t("aria2 başlatılamadı. ", "Could not start aria2. ") + lastError) }
        }
        // Bitince paylaşım: kapalıysa hemen durur, açıksa oran 1.0'a ulaşana kadar paylaşır.
        _ = try await call("aria2.changeGlobalOption", [[
            "max-overall-download-limit": String(speedLimit),
            "seed-time": seeding ? "60" : "0",
            "seed-ratio": seeding ? "1.0" : "0.0",
        ]])
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }

    // MARK: Komutlar

    /// Magnet veya .torrent bağlantısı ekler; aria2'nin verdiği kimliği (GID) döndürür.
    func addURI(_ uri: String, folder: URL) async throws -> String {
        try await call("aria2.addUri", [[uri], ["dir": folder.path]]) as? String ?? ""
    }

    /// Yerel .torrent dosyasının içeriğini ekler.
    func addTorrent(_ data: Data, folder: URL) async throws -> String {
        try await call("aria2.addTorrent", [data.base64EncodedString(), [String](), ["dir": folder.path]]) as? String ?? ""
    }

    func status(_ gid: String) async throws -> [String: Any] {
        try await call("aria2.tellStatus", [gid]) as? [String: Any] ?? [:]
    }

    /// İndirmeyi durdurur; dosyalar ve devam bilgisi (.aria2) diskte kalır, yeniden eklenince kaldığı yerden sürer.
    func remove(_ gid: String) async {
        _ = try? await call("aria2.forceRemove", [gid])
        _ = try? await call("aria2.removeDownloadResult", [gid])
    }

    // MARK: JSON-RPC

    @discardableResult
    func call(_ method: String, _ params: [Any]) async throws -> Any? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": UUID().uuidString, "method": method, "params": ["token:\(secret)"] + params]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EngineError.failed("aria2: geçersiz yanıt") }
        if let error = json["error"] as? [String: Any] { throw EngineError.failed(error["message"] as? String ?? "aria2") }
        return json["result"]
    }

    // MARK: Yardımcılar

    /// aria2'nin onaltılık parça bit alanını `bins` bölmeye indirger (her bölme: inmiş parçaların oranı).
    static func pieceMap(bitfield: String, pieces: Int, bins: Int = 64) -> [Double] {
        var have = [Bool](); have.reserveCapacity(pieces)
        for ch in bitfield {
            guard let nibble = ch.hexDigitValue else { continue }
            for bit in (0..<4).reversed() where have.count < pieces { have.append(nibble >> bit & 1 == 1) }
        }
        while have.count < pieces { have.append(false) }
        let n = min(bins, pieces)
        return (0..<n).map { b in
            let lo = b * pieces / n, hi = max(lo + 1, (b + 1) * pieces / n)
            return Double(have[lo..<hi].filter { $0 }.count) / Double(hi - lo)
        }
    }

    static func isMagnet(_ url: URL) -> Bool { url.scheme?.lowercased() == "magnet" }
    static func isTorrentLink(_ url: URL) -> Bool { isMagnet(url) || url.pathExtension.lowercased() == "torrent" }

    /// Magnet bağlantısındaki görünen ad (dn=…), yoksa bilgi özeti.
    static func displayName(_ url: URL) -> String {
        let items = URLComponents(string: url.absoluteString)?.queryItems ?? []
        if let dn = items.first(where: { $0.name == "dn" })?.value, !dn.isEmpty { return dn }
        if let xt = items.first(where: { $0.name == "xt" })?.value { return "Torrent " + String(xt.split(separator: ":").last ?? "").prefix(12) }
        return url.lastPathComponent.isEmpty ? "Torrent" : url.lastPathComponent
    }

    /// aria2 durumundan torrentin adı (bilgi sözlüğündeki ad veya ilk dosya).
    static func name(from status: [String: Any]) -> String? {
        if let bt = status["bittorrent"] as? [String: Any], let info = bt["info"] as? [String: Any], let name = info["name"] as? String, !name.isEmpty { return name }
        if let files = status["files"] as? [[String: Any]], let path = files.first?["path"] as? String, !path.isEmpty, !path.hasPrefix("[METADATA]") {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return nil
    }
}
