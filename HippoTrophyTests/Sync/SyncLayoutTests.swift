import Foundation
import Testing
@testable import HippoTrophy

struct SyncLayoutTests {
    private func layout(_ text: String) throws -> SyncLayout {
        try SyncLayout.parse(text).get()
    }

    @Test func takesAnAddressWithoutSchemeAsHTTPS() throws {
        #expect(try layout("cloud.example.com/dav").server.absoluteString == "https://cloud.example.com/dav/")
    }

    @Test func putsItsFolderInsideThePathGiven() throws {
        let layout = try layout("https://cloud.example.com/remote.php/dav/files/alex")
        #expect(layout.folder.absoluteString == "https://cloud.example.com/remote.php/dav/files/alex/HippoTrophy/")
        #expect(layout.backup.absoluteString == "https://cloud.example.com/remote.php/dav/files/alex/HippoTrophy/backup.zip")
        #expect(layout.uploading.lastPathComponent == "backup.zip.uploading")
        #expect(layout.history.absoluteString.hasSuffix("/HippoTrophy/history/"))
    }

    @Test func keepsAPortAndASlashAlreadyThere() throws {
        #expect(try layout("https://nas.example.test:8443/webdav/").folder.absoluteString == "https://nas.example.test:8443/webdav/HippoTrophy/")
    }

    @Test func refusesPlainHTTP() {
        #expect(throws: SyncLayout.AddressProblem.notHTTPS) { try SyncLayout.parse("http://cloud.example.com/dav").get() }
    }

    @Test func refusesWhatIsNoServerAddress() {
        #expect(throws: SyncLayout.AddressProblem.empty) { try SyncLayout.parse("  ").get() }
        #expect(throws: SyncLayout.AddressProblem.invalid) { try SyncLayout.parse("https://").get() }
        #expect(throws: SyncLayout.AddressProblem.invalid) { try SyncLayout.parse("https://alex:secret@cloud.example.com/").get() }
        #expect(throws: SyncLayout.AddressProblem.invalid) { try SyncLayout.parse("https://cloud.example.com/?dir=x").get() }
    }

    @Test func namesTheDailyCopyByTheLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 23:30 UTC is already the next day in Berlin.
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-13T23:30:00Z"))
        #expect(SyncLayout.historyName(for: date, calendar: calendar) == "2026-11-14.zip")
    }

    @Test func keepsTheNewestFourteenDailyCopies() {
        let days = (1...16).map { String(format: "2026-10-%02d.zip", $0) }
        #expect(SyncLayout.historyToDelete(among: days.shuffled()) == ["2026-10-02.zip", "2026-10-01.zip"])
    }

    @Test func leavesAloneWhatIsNoDailyCopy() {
        let names = (1...20).map { String(format: "2026-10-%02d.zip", $0) } + ["notes.txt", "2026-10-01.zip.bak", "old.zip"]
        let doomed = SyncLayout.historyToDelete(among: names)
        #expect(doomed.count == 6)
        #expect(doomed.allSatisfy(SyncLayout.isHistoryName))
    }
}
