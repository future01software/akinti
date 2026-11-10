import Foundation

/// Dosyanın bir bölümü (bayt aralığı, `end` dahil). IDM'deki "bağlantı" karşılığı.
struct Segment: Codable, Equatable {
    var start: Int64
    var end: Int64
    var received: Int64 = 0
    var length: Int64 { end - start + 1 }
    var isDone: Bool { received >= length }
    var next: Int64 { start + received }
}

/// Tüm indirmelerin paylaştığı hız sınırlayıcı (token bucket). 0 = sınırsız.
final class RateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var rate: Double = 0
    private var allowance: Double = 0
    private var last = Date()

    var bytesPerSecond: Double {
        get { lock.lock(); defer { lock.unlock() }; return rate }
        set { lock.lock(); rate = max(0, newValue); allowance = 0; last = Date(); lock.unlock() }
    }

    /// `n` bayt için izin alır; sınır aşılıyorsa çağıran kuyruğu bekletir (bu da sunucuyu TCP ile yavaşlatır).
    func consume(_ n: Int) {
        lock.lock()
        guard rate > 0 else { lock.unlock(); return }
        let now = Date()
        allowance = min(rate, allowance + now.timeIntervalSince(last) * rate)
        last = now
        allowance -= Double(n)
        let wait = allowance < 0 ? -allowance / rate : 0
        lock.unlock()
        if wait > 0 { usleep(useconds_t(min(wait, 2) * 1_000_000)) }
    }
}

enum HTTPJobResult {
    case finished(suggestedName: String?)
    case cancelled
    case failed(message: String, status: Int?, retryable: Bool)
}

/// Bir HTTP indirmesi. Sunucu bayt aralıklarını destekliyorsa dosyayı parçalara bölüp
/// birden fazla bağlantıyla aynı anda indirir; desteklemiyorsa tek bağlantı kullanır.
/// Tüm dosya yazma ve durum işlemleri tek bir seri kuyrukta yapılır.
final class HTTPJob: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static var minimumSegmentSize: Int64 = 1 << 20 // 1 MB'den küçük parçaya bölme (testlerde küçültülür)

    var onProgress: (([Segment], Int64) -> Void)?
    var onFinish: ((HTTPJobResult) -> Void)?

    private let url: URL
    private let partURL: URL
    private let connections: Int
    private let limiter: RateLimiter
    private let queue = DispatchQueue(label: "akinti.http")
    private lazy var session: URLSession = {
        let ops = OperationQueue()
        ops.underlyingQueue = queue
        ops.maxConcurrentOperationCount = 1
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: ops)
    }()

    private var segments: [Segment]
    private var total: Int64
    private var rangesSupported: Bool
    private var handle: FileHandle?
    private var tasks: [Int: Int] = [:]          // task id -> segment index
    private var taskRefs: [Int: URLSessionDataTask] = [:]
    private var suggestedName: String?
    private var ended = false
    private var lastReport = Date.distantPast

    /// Tarayıcı eklentisinden gelen bilgiler: bazı sunucular dosyayı yalnızca doğru Referer/User-Agent ile verir.
    var referrer: String?
    var userAgent: String?

    init(url: URL, partURL: URL, segments: [Segment]?, total: Int64, connections: Int, limiter: RateLimiter) {
        self.url = url
        self.partURL = partURL
        self.connections = max(1, min(16, connections))
        self.limiter = limiter
        // Kayıtlı parçalar ve yarım dosya varsa kaldığı yerden devam edilir.
        let canResume = (segments?.isEmpty == false) && total > 0 && FileManager.default.fileExists(atPath: partURL.path)
        self.segments = canResume ? segments! : []
        self.total = canResume ? total : 0
        self.rangesSupported = canResume
    }

    func start() {
        queue.async { [self] in
            do {
                if !FileManager.default.fileExists(atPath: partURL.path) || segments.isEmpty {
                    try FileManager.default.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: partURL.path, contents: nil)
                }
                handle = try FileHandle(forWritingTo: partURL)
            } catch {
                return finish(.failed(message: error.localizedDescription, status: nil, retryable: false))
            }
            if segments.isEmpty {
                // İlk istek: "bytes=0-" ile sunucunun parçalı indirmeyi destekleyip desteklemediği anlaşılır.
                launch(segmentIndex: nil, range: "bytes=0-")
            } else {
                for i in segments.indices where !segments[i].isDone { launch(segmentIndex: i) }
                if tasks.isEmpty { complete() }
            }
        }
    }

    /// Duraklat: bağlantılar kapanır, parçaların ilerlemesi korunur.
    func cancel() {
        queue.async { [self] in finish(.cancelled) }
    }

    var snapshot: ([Segment], Int64) { queue.sync { (segments, total) } }

    // MARK: İstekler

    private func launch(segmentIndex: Int?, range: String? = nil) {
        var request = URLRequest(url: url)
        if let referrer { request.setValue(referrer, forHTTPHeaderField: "Referer") }
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let i = segmentIndex {
            request.setValue("bytes=\(segments[i].next)-\(segments[i].end)", forHTTPHeaderField: "Range")
        } else if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        tasks[task.taskIdentifier] = segmentIndex ?? -1
        taskRefs[task.taskIdentifier] = task
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !ended, let http = response as? HTTPURLResponse, let index = tasks[dataTask.taskIdentifier] else { return completionHandler(.cancel) }
        let status = http.statusCode
        guard (200...299).contains(status) else {
            completionHandler(.cancel)
            return finish(.failed(message: t("Sunucu HTTP \(status) döndürdü.", "Server returned HTTP \(status)."),
                                  status: status, retryable: [408, 429, 500, 502, 503, 504].contains(status)))
        }
        if suggestedName == nil { suggestedName = response.suggestedFilename }

        if index == -1 {
            // İlk yanıt: parçalara bölme kararı burada verilir.
            if status == 206, let size = Self.totalSize(from: http), size > 0 {
                rangesSupported = true
                total = size
                segments = Self.split(size: size, connections: connections)
                tasks[dataTask.taskIdentifier] = 0 // ilk bağlantı 0. parçayı indirir, sonu gelince kesilir
                for i in segments.indices.dropFirst() { launch(segmentIndex: i) }
            } else {
                // Aralık desteği yok: tek bağlantı, baştan.
                rangesSupported = false
                total = max(0, http.expectedContentLength)
                segments = [Segment(start: 0, end: total > 0 ? total - 1 : Int64.max - 1)]
                try? handle?.truncate(atOffset: 0)
                tasks[dataTask.taskIdentifier] = 0
            }
            report(force: true)
        } else if status != 206 {
            // Devam isteğine sunucu tüm dosyayla yanıt verdi: parçalı devam mümkün değil, baştan başla.
            completionHandler(.cancel)
            restartFromScratch()
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !ended, let i = tasks[dataTask.taskIdentifier], i >= 0, i < segments.count, let handle else { return }
        let remaining = segments[i].length - segments[i].received
        guard remaining > 0 else { dataTask.cancel(); return }
        let chunk = Int64(data.count) > remaining ? data.prefix(Int(remaining)) : data
        limiter.consume(chunk.count)
        guard !ended else { return }
        do {
            try handle.seek(toOffset: UInt64(segments[i].next))
            try handle.write(contentsOf: chunk)
        } catch {
            return finish(.failed(message: error.localizedDescription, status: nil, retryable: false))
        }
        segments[i].received += Int64(chunk.count)
        if segments[i].isDone {
            tasks[dataTask.taskIdentifier] = nil
            dataTask.cancel()
            if tasks.isEmpty { return complete() }
        }
        report()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        taskRefs[task.taskIdentifier] = nil
        guard !ended, let i = tasks.removeValue(forKey: task.taskIdentifier) else { return }
        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled { return }
            let retryable = error.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
                                                                 NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost].contains(error.code)
            return finish(.failed(message: error.localizedDescription, status: nil, retryable: retryable))
        }
        // Boyutu bilinmeyen tek bağlantılı indirme: bağlantı bitince dosya tamamdır.
        if i >= 0, i < segments.count, !rangesSupported, total == 0 {
            segments[i].end = segments[i].received - 1
            total = segments[i].received
        }
        if i >= 0, i < segments.count, !segments[i].isDone {
            return finish(.failed(message: t("Bağlantı erken kapandı.", "The connection closed early."), status: nil, retryable: true))
        }
        if tasks.isEmpty { complete() }
    }

    // MARK: Yardımcılar

    private func restartFromScratch() {
        for task in taskRefs.values { task.cancel() }
        tasks.removeAll(); taskRefs.removeAll()
        segments = []
        total = 0
        rangesSupported = false
        try? handle?.truncate(atOffset: 0)
        launch(segmentIndex: nil, range: "bytes=0-")
    }

    private func complete() {
        guard segments.allSatisfy(\.isDone) else { return }
        finish(.finished(suggestedName: suggestedName))
    }

    private func finish(_ result: HTTPJobResult) {
        guard !ended else { return }
        ended = true
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        session.invalidateAndCancel()
        let segments = self.segments, total = self.total
        DispatchQueue.main.async { [self] in
            onProgress?(segments, total)
            onFinish?(result)
            onProgress = nil; onFinish = nil
        }
    }

    private func report(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.2 else { return }
        lastReport = now
        let segments = self.segments, total = self.total
        DispatchQueue.main.async { [weak self] in self?.onProgress?(segments, total) }
    }

    static func totalSize(from response: HTTPURLResponse) -> Int64? {
        // Content-Range: bytes 0-1023/4096
        guard let value = response.value(forHTTPHeaderField: "Content-Range"), let slash = value.lastIndex(of: "/") else { return nil }
        return Int64(value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    static func split(size: Int64, connections: Int) -> [Segment] {
        let count = Int(max(1, min(Int64(connections), size / minimumSegmentSize)))
        let base = size / Int64(count)
        return (0..<count).map { i in
            let start = Int64(i) * base
            let end = i == count - 1 ? size - 1 : start + base - 1
            return Segment(start: start, end: end)
        }
    }
}
