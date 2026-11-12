import Testing
@testable import HippoTrophy

/// `CountFormat` is the one place a count picks its word, so these pin down
/// which number gets which form — the reason it exists was "1 sets".
struct CountFormatTests {
    @Test func oneTakesTheSingular() {
        #expect(CountFormat.text(1, "set", "sets") == "1 set")
        #expect(CountFormat.text(1, "exercise", "exercises") == "1 exercise")
    }

    /// Zero reads as a plural in English: "0 sets", not "0 set".
    @Test func zeroAndManyTakeThePlural() {
        #expect(CountFormat.text(0, "set", "sets") == "0 sets")
        #expect(CountFormat.text(2, "set", "sets") == "2 sets")
        #expect(CountFormat.text(21, "set", "sets") == "21 sets")
    }

    /// The forms are whatever was written down, so a verb that agrees with the
    /// count comes along with it.
    @Test func theFormsCanCarryTheirVerb() {
        #expect(CountFormat.text(1, "exercise was", "exercises were") == "1 exercise was")
        #expect(CountFormat.text(3, "exercise was", "exercises were") == "3 exercises were")
    }
}
