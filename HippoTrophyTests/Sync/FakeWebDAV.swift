import Foundation

/// A WebDAV server in memory, as far as the sync uses one: folders, files with
/// etags, PROPFIND at depth 0 and 1, MKCOL, PUT, MOVE, COPY, DELETE, Basic
/// Auth. Each server answers on a host of its own, so tests running side by
/// side do not meet.
final class FakeWebDAV: @unchecked Sendable {
    struct File {
        var data: Data
        var etag: String
    }

    let host = "\(UUID().uuidString.lowercased()).example.test"
    let user = "alex"
    let password = "app-password"
    /// The address a user would type.
    var address: String { "https://\(host)/dav/" }

    private let lock = NSLock()
    private var _files: [String: File] = [:]
    private var folders: Set<String> = ["/dav"]
    private var _log: [String] = []
    private var etagCounter = 0
    /// Every request gets this status instead of an answer, while set.
    private var _forcedStatus: Int?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: FakeWebDAV] = [:]

    init() {
        Self.lock.withLock { Self.servers[host] = self }
    }

    static func server(for host: String?) -> FakeWebDAV? {
        guard let host else { return nil }
        return lock.withLock { servers[host] }
    }

    /// A session that reaches this server and nothing else.
    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeWebDAVProtocol.self]
        return URLSession(configuration: configuration)
    }

    var files: [String: File] { lock.withLock { _files } }
    var log: [String] { lock.withLock { _log } }
    var forcedStatus: Int? {
        get { lock.withLock { _forcedStatus } }
        set { lock.withLock { _forcedStatus = newValue } }
    }

    func clearLog() { lock.withLock { _log = [] } }

    /// Puts a file there as someone else would.
    func place(_ data: Data, at path: String) {
        lock.withLock {
            var folder = path
            while let slash = folder.lastIndex(of: "/"), slash != folder.startIndex {
                folder = String(folder[..<slash])
                folders.insert(folder)
            }
            _files[path] = File(data: data, etag: nextETag())
        }
    }

    // MARK: - Answering

    func answer(_ request: URLRequest, body: Data) -> (status: Int, data: Data) {
        lock.withLock {
            let method = request.httpMethod ?? "GET"
            let path = Self.path(of: request.url)
            _log.append("\(method) \(path)")
            if let _forcedStatus { return (_forcedStatus, Data()) }
            let expected = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
            guard request.value(forHTTPHeaderField: "Authorization") == expected else { return (401, Data()) }

            switch method {
            case "PROPFIND":
                let depth = request.value(forHTTPHeaderField: "Depth") ?? "1"
                if let file = _files[path] {
                    return (207, multistatus([(path, file.etag, false)]))
                }
                guard folders.contains(path) else { return (404, Data()) }
                var entries = [(path + "/", nil as String?, true)]
                if depth == "1" {
                    entries += folders.filter { parent(of: $0) == path }.sorted().map { ($0 + "/", nil, true) }
                    entries += _files.filter { parent(of: $0.key) == path }.sorted { $0.key < $1.key }.map { ($0.key, $0.value.etag, false) }
                }
                return (207, multistatus(entries))
            case "MKCOL":
                if folders.contains(path) || _files[path] != nil { return (405, Data()) }
                guard folders.contains(parent(of: path)) else { return (409, Data()) }
                folders.insert(path)
                return (201, Data())
            case "PUT":
                guard folders.contains(parent(of: path)) else { return (409, Data()) }
                let existed = _files[path] != nil
                _files[path] = File(data: body, etag: nextETag())
                return (existed ? 204 : 201, Data())
            case "MOVE", "COPY":
                guard let source = _files[path] else { return (404, Data()) }
                let destination = Self.path(of: request.value(forHTTPHeaderField: "Destination").flatMap(URL.init(string:)))
                guard folders.contains(parent(of: destination)) else { return (409, Data()) }
                let existed = _files[destination] != nil
                _files[destination] = File(data: source.data, etag: nextETag())
                if method == "MOVE" { _files[path] = nil }
                return (existed ? 204 : 201, Data())
            case "DELETE":
                return _files.removeValue(forKey: path) == nil ? (404, Data()) : (204, Data())
            default:
                return (405, Data())
            }
        }
    }

    private func nextETag() -> String {
        etagCounter += 1
        return "\"\(etagCounter)\""
    }

    private func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    private static func path(of url: URL?) -> String {
        let path = url?.path(percentEncoded: false) ?? ""
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func multistatus(_ entries: [(href: String, etag: String?, collection: Bool)]) -> Data {
        let responses = entries.map { entry in
            """
            <D:response><D:href>\(entry.href)</D:href><D:propstat><D:prop>\
            \(entry.etag.map { "<D:getetag>\($0)</D:getetag>" } ?? "")\
            <D:resourcetype>\(entry.collection ? "<D:collection/>" : "")</D:resourcetype>\
            </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
            """
        }
        return Data("<?xml version=\"1.0\"?><D:multistatus xmlns:D=\"DAV:\">\(responses.joined())</D:multistatus>".utf8)
    }
}

final class FakeWebDAVProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        FakeWebDAV.server(for: request.url?.host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = FakeWebDAV.server(for: url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let (status, data) = server.answer(request, body: Self.body(of: request))
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A body handed to URLSession reaches a protocol as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
