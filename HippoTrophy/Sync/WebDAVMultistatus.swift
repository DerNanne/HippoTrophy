import Foundation

/// What a WebDAV server answers to PROPFIND: one response per resource, with
/// the properties the sync asks for. Read by namespace, not by prefix — one
/// server writes `d:getetag`, another `D:getetag`, a third no prefix at all.
nonisolated struct WebDAVMultistatus: Equatable {
    struct Resource: Equatable {
        /// As the server spells it, percent-encoded.
        var href: String
        var etag: String?
        var isCollection: Bool

        /// The last part of the path, decoded: `2026-11-13.zip`.
        var name: String {
            let path = href.hasSuffix("/") ? String(href.dropLast()) : href
            let last = path.split(separator: "/").last.map(String.init) ?? ""
            return last.removingPercentEncoding ?? last
        }
    }

    var resources: [Resource]

    /// The body the sync sends: only the two properties it reads.
    static let request = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:resourcetype/></d:prop></d:propfind>
        """.utf8)

    static func parse(_ data: Data) throws -> WebDAVMultistatus {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse() else { throw WebDAVError.unreadableAnswer }
        return WebDAVMultistatus(resources: reader.resources)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var resources: [Resource] = []
        private var current: Resource?
        private var text = ""
        /// Inside a propstat whose status is not 200, the properties are the
        /// ones the server does not have: an etag there is no etag.
        private var propstatFailed = false
        private var pendingETag: String?
        private var pendingCollection = false

        func parser(
            _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
            qualifiedName: String?, attributes: [String: String] = [:]
        ) {
            guard namespaceURI == "DAV:" else { return }
            text = ""
            switch element {
            case "response": current = Resource(href: "", etag: nil, isCollection: false)
            case "propstat":
                propstatFailed = false
                pendingETag = nil
                pendingCollection = false
            case "collection": pendingCollection = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            guard namespaceURI == "DAV:" else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "href" where current?.href.isEmpty == true: current?.href = value
            case "getetag": pendingETag = value.isEmpty ? nil : value
            case "status": propstatFailed = !value.contains(" 200 ")
            case "propstat":
                if !propstatFailed {
                    if let pendingETag { current?.etag = pendingETag }
                    if pendingCollection { current?.isCollection = true }
                }
            case "response":
                if let current { resources.append(current) }
                current = nil
            default: break
            }
            text = ""
        }
    }
}
