import Foundation
import Testing
@testable import HippoTrophy

struct WebDAVMultistatusTests {
    @Test func readsAnswersWhateverThePrefix() throws {
        let answer = """
            <?xml version="1.0"?>
            <d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
              <d:response>
                <d:href>/remote.php/dav/files/alex/HippoTrophy/</d:href>
                <d:propstat><d:prop><d:getetag>"abc"</d:getetag><d:resourcetype><d:collection/></d:resourcetype></d:prop>
                <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
              </d:response>
              <d:response>
                <d:href>/remote.php/dav/files/alex/HippoTrophy/backup.zip</d:href>
                <d:propstat><d:prop><d:getetag>"def"</d:getetag><d:resourcetype/></d:prop>
                <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
              </d:response>
            </d:multistatus>
            """
        let other = answer.replacingOccurrences(of: "d:", with: "D:").replacingOccurrences(of: "xmlns:d=", with: "xmlns:D=")
        for text in [answer, other] {
            let resources = try WebDAVMultistatus.parse(Data(text.utf8)).resources
            #expect(resources.map(\.name) == ["HippoTrophy", "backup.zip"])
            #expect(resources.map(\.etag) == ["\"abc\"", "\"def\""])
            #expect(resources.map(\.isCollection) == [true, false])
        }
    }

    @Test func takesNoEtagFromAPropertyTheServerDoesNotHave() throws {
        let answer = """
            <D:multistatus xmlns:D="DAV:">
              <D:response>
                <D:href>/dav/HippoTrophy/history/</D:href>
                <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
                <D:status>HTTP/1.1 200 OK</D:status></D:propstat>
                <D:propstat><D:prop><D:getetag/></D:prop>
                <D:status>HTTP/1.1 404 Not Found</D:status></D:propstat>
              </D:response>
            </D:multistatus>
            """
        let resource = try #require(try WebDAVMultistatus.parse(Data(answer.utf8)).resources.first)
        #expect(resource.etag == nil)
        #expect(resource.isCollection)
    }

    @Test func decodesTheName() {
        let resource = WebDAVMultistatus.Resource(href: "/dav/My%20Folder/2026-11-13.zip", etag: nil, isCollection: false)
        #expect(resource.name == "2026-11-13.zip")
        #expect(WebDAVMultistatus.Resource(href: "/dav/My%20Folder/", etag: nil, isCollection: true).name == "My Folder")
    }

    @Test func refusesWhatIsNoXML() {
        #expect(throws: WebDAVError.unreadableAnswer) { try WebDAVMultistatus.parse(Data("<html><body>Login".utf8)) }
    }
}
