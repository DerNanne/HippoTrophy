import Foundation
import Testing
@testable import HippoTrophy

struct SupportTests {
    /// The prefilled text reaches the mail app, spaces and all.
    @Test func aMailCarriesItsSubjectAndBody() throws {
        let url = try #require(Support.mail(subject: "Help with the migration", body: "Please attach the backup."))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.scheme == "mailto")
        #expect(items.first { $0.name == "subject" }?.value == "Help with the migration")
        #expect(items.first { $0.name == "body" }?.value == "Please attach the backup.")
    }

    @Test func withoutABodyThereIsNone() throws {
        let url = try #require(Support.mail(subject: "Old backup"))
        #expect(!url.absoluteString.contains("body="))
    }
}
