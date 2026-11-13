import Foundation

nonisolated enum WebDAVError: Error, Equatable {
    /// The server answered, with a status the step does not accept.
    case status(Int)
    /// A PROPFIND answer that is no multistatus.
    case unreadableAnswer
}

/// The few WebDAV requests the sync needs, with Basic Auth over HTTPS. Knows
/// nothing about backups or folders of its own: it is told the URLs.
nonisolated struct WebDAVClient: Sendable {
    let user: String
    let password: String
    var session: URLSession = .shared

    /// The etag of a file, nil when there is none there.
    func etag(of url: URL) async throws -> String? {
        let (data, status) = try await send("PROPFIND", to: url, body: WebDAVMultistatus.request, headers: ["Depth": "0"])
        if status == 404 { return nil }
        try expect(status, in: [207])
        return try WebDAVMultistatus.parse(data).resources.first?.etag
    }

    /// What is in a folder, without the folder itself. A missing folder is
    /// an empty one.
    func list(_ folder: URL) async throws -> [WebDAVMultistatus.Resource] {
        let (data, status) = try await send("PROPFIND", to: folder, body: WebDAVMultistatus.request, headers: ["Depth": "1"])
        if status == 404 { return [] }
        try expect(status, in: [207])
        let own = folder.path(percentEncoded: false)
        return try WebDAVMultistatus.parse(data).resources.filter { resource in
            let path = URL(string: resource.href, relativeTo: folder)?.path(percentEncoded: false) ?? resource.href
            return path.trimmingSuffix("/") != own.trimmingSuffix("/")
        }
    }

    /// A file's content, nil when there is none there.
    func get(_ url: URL) async throws -> Data? {
        let (data, status) = try await send("GET", to: url)
        if status == 404 { return nil }
        try expect(status, in: [200])
        return data
    }

    /// Makes a folder; one already there is fine. 405 is what RFC 4918 has a
    /// server say when the folder exists.
    func makeFolder(_ url: URL) async throws {
        let (_, status) = try await send("MKCOL", to: url)
        try expect(status, in: [201, 405])
    }

    func put(_ data: Data, to url: URL) async throws {
        let (_, status) = try await send("PUT", to: url, body: data, headers: ["Content-Type": "application/zip"])
        try expect(status, in: [200, 201, 204])
    }

    /// Moves a file over another; the one in the way is replaced.
    func move(_ source: URL, to destination: URL) async throws {
        let (_, status) = try await send("MOVE", to: source, headers: ["Destination": destination.absoluteString, "Overwrite": "T"])
        try expect(status, in: [201, 204])
    }

    /// Copies a file over another; the one in the way is replaced.
    func copy(_ source: URL, to destination: URL) async throws {
        let (_, status) = try await send("COPY", to: source, headers: ["Destination": destination.absoluteString, "Overwrite": "T"])
        try expect(status, in: [201, 204])
    }

    /// Deletes a file; one already gone is fine.
    func delete(_ url: URL) async throws {
        let (_, status) = try await send("DELETE", to: url)
        try expect(status, in: [200, 204, 404])
    }

    // MARK: -

    private func send(_ method: String, to url: URL, body: Data? = nil, headers: [String: String] = [:]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        let credentials = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func expect(_ status: Int, in accepted: Set<Int>) throws {
        guard accepted.contains(status) else { throw WebDAVError.status(status) }
    }
}

private extension String {
    nonisolated func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
