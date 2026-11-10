import Foundation

/// Tarayıcı eklentisinden Akıntı'ya gelen indirme isteği.
///
/// Biçim: `akinti://add?u=<bağlantı>&u=<bağlantı>&ref=<yönlendiren>&ua=<user-agent>&mode=video`
/// Akıntı bu isteği hiçbir zaman kendiliğinden indirmez; önce ekleme penceresinde gösterir.
public struct AkintiLink: Equatable {
    public static let scheme = "akinti"

    public var urls: [URL]
    public var referrer: String?
    public var userAgent: String?
    /// "video": bağlantılar video sayfası olarak işlenir (ör. YouTube sayfası). nil: otomatik.
    public var mode: String?

    public init(urls: [URL], referrer: String? = nil, userAgent: String? = nil, mode: String? = nil) {
        self.urls = urls; self.referrer = referrer; self.userAgent = userAgent; self.mode = mode
    }

    /// Yalnızca http, https ve magnet bağlantıları kabul edilir.
    public static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host != nil
        case "magnet": return true
        default: return false
        }
    }

    public var url: URL? {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "add"
        var items = urls.map { URLQueryItem(name: "u", value: $0.absoluteString) }
        if let referrer, !referrer.isEmpty { items.append(URLQueryItem(name: "ref", value: referrer)) }
        if let userAgent, !userAgent.isEmpty { items.append(URLQueryItem(name: "ua", value: userAgent)) }
        if let mode, !mode.isEmpty { items.append(URLQueryItem(name: "mode", value: mode)) }
        c.queryItems = items
        // "+" ve "&" gibi karakterler değer içinde güvenle taşınsın.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    public static func parse(_ url: URL) -> AkintiLink? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "add",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let urls = items.filter { $0.name == "u" }.compactMap { $0.value.flatMap(URL.init(string:)) }.filter(isAllowed)
        guard !urls.isEmpty else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : String($0.prefix(2048)) } }
        return AkintiLink(urls: Array(urls.prefix(500)), referrer: value("ref"), userAgent: value("ua"), mode: value("mode"))
    }
}

/// Native Messaging: her mesaj 4 baytlık (yerel bayt sırası) uzunluk + UTF-8 JSON'dur.
public enum NativeMessage {
    public static let hostName = "com.akinti.bridge"
    /// En büyük mesaj (Chrome'un tarayıcıya gönderim sınırı 1 MB; gelen mesajlar için de makul bir sınır).
    public static let maxLength = 1 << 20

    public static func encode(_ object: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(json.count).littleEndian
        return Data(bytes: &length, count: 4) + json
    }

    /// Okuyucudan bir mesaj okur; akış bittiyse nil.
    public static func read(from handle: FileHandle) throws -> [String: Any]? {
        guard let header = try handle.read(upToCount: 4), header.count == 4 else { return nil }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        guard length > 0, length <= maxLength, let body = try handle.read(upToCount: length), body.count == length else { return nil }
        return try JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}
