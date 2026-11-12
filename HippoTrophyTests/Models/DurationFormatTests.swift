import Testing
@testable import HippoTrophy

/// `DurationFormat` is where a stored number becomes a duration and back. The
/// free-text reader is the interesting half: it guesses, and the tests below
/// pin down what it guesses so a change to the rule cannot pass unnoticed.
struct DurationFormatTests {
    @Test func writesMinutesWithoutAnHour() {
        #expect(DurationFormat.text(forSeconds: 510) == "8:30")
        #expect(DurationFormat.text(forSeconds: 45) == "0:45")
        #expect(DurationFormat.text(forSeconds: 5025) == "1:23:45")
    }

    @Test func readsTheColonSpellingABackupWrites() {
        #expect(DurationFormat.seconds(fromColonText: "30:30") == 1830)
        #expect(DurationFormat.seconds(fromColonText: "1:23:45") == 5025)
        #expect(DurationFormat.seconds(fromColonText: " 8:30 ") == 510)
    }

    /// Without a colon there is nothing to read, rather than a number to guess
    /// at — which is why a backup spells a duration with one.
    @Test func refusesAValueWithoutAColon() {
        #expect(DurationFormat.seconds(fromColonText: "830") == nil)
        #expect(DurationFormat.seconds(fromColonText: "") == nil)
        #expect(DurationFormat.seconds(fromColonText: "1:2:3:4") == nil)
    }

    @Test func readsFreeTextRightToLeftLikeAStopwatch() {
        #expect(DurationFormat.seconds(fromFreeText: "830") == 510)
        #expect(DurationFormat.seconds(fromFreeText: "45") == 45)
        #expect(DurationFormat.seconds(fromFreeText: "8:30") == 510)
    }

    /// Documented, not desired: a bare number of seconds is read as minutes and
    /// seconds, and comes back smaller. This is why a backup never spells a
    /// duration without a colon.
    @Test func aBareSecondCountIsNotReadBackAsItself() {
        #expect(DurationFormat.seconds(fromFreeText: "480") == 320)
        let once = DurationFormat.seconds(fromFreeText: "510")
        #expect(once == 310)
        #expect(once != 510)
    }

    @Test func emptyPiecesCountAsZeroButLettersDoNot() {
        #expect(DurationFormat.seconds(fromFreeText: "8:") == 480)
        #expect(DurationFormat.seconds(fromFreeText: ":30") == 30)
        #expect(DurationFormat.seconds(fromFreeText: "abc") == nil)
        #expect(DurationFormat.seconds(fromFreeText: "") == nil)
        #expect(DurationFormat.seconds(fromFreeText: "   ") == nil)
    }

    /// A minus sign is not a whole number, so a negative duration is refused
    /// rather than silently turned positive.
    @Test func refusesANegativeValue() {
        #expect(DurationFormat.seconds(fromFreeText: "-5") == nil)
    }

    @Test func clampsAtOneDay() {
        #expect(DurationFormat.maxSeconds == 86399)
        #expect(DurationFormat.seconds(fromFreeText: "999999") == 86399)
        #expect(DurationFormat.seconds(fromFreeText: "9999999") == 86399)
        #expect(DurationFormat.seconds(fromColonText: "99:99:99") == 86399)
        #expect(DurationFormat.clampedSeconds(hours: 30, minutes: 0, seconds: 0) == 86399)
    }

    @Test func componentsAndClampingAreEachOthersInverse() {
        let parts = DurationFormat.components(fromSeconds: 5025)
        #expect(parts == (1, 23, 45))
        #expect(DurationFormat.clampedSeconds(hours: 1, minutes: 23, seconds: 45) == 5025)
        #expect(DurationFormat.components(fromSeconds: -10) == (0, 0, 0))
    }
}
