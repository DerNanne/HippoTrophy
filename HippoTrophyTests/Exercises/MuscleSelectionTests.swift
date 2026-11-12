import Foundation
import Testing
@testable import HippoTrophy

struct MuscleSelectionTests {
    /// Main or secondary or neither — never both.
    @Test func aMuscleIsMainOrSecondaryNeverBoth() {
        var selection = MuscleSelection(primary: [], secondary: [])
        selection.toggle(.quads, .primary)
        #expect(selection == MuscleSelection(primary: ["quads"], secondary: []))
        selection.toggle(.quads, .secondary)
        #expect(selection == MuscleSelection(primary: [], secondary: ["quads"]))
        #expect(selection.level(of: .quads) == .secondary)
    }

    @Test func pickingTheLevelAgainClearsIt() {
        var selection = MuscleSelection(primary: ["quads"], secondary: ["adductors"])
        selection.toggle(.quads, .primary)
        selection.toggle(.adductors, .secondary)
        #expect(selection == MuscleSelection(primary: [], secondary: []))
    }

    @Test func picksKeepTheirOrder() {
        var selection = MuscleSelection(primary: ["quads"], secondary: [])
        selection.toggle(.glutes, .primary)
        selection.toggle(.adductors, .secondary)
        #expect(selection.primary == ["quads", "glutes"])
        #expect(selection.secondary == ["adductors"])
    }

    @Test func onlyStrengthWithoutAnyMuscleAsksBeforeSaving() {
        let none = MuscleSelection(primary: [], secondary: [])
        #expect(none.asksBeforeSaving(categoryName: "Strength"))
        #expect(none.asksBeforeSaving(categoryName: "strength"))
        #expect(!none.asksBeforeSaving(categoryName: "Cardio"))
        #expect(!none.asksBeforeSaving(categoryName: ""))
        #expect(!MuscleSelection(primary: ["chest"], secondary: []).asksBeforeSaving(categoryName: "Strength"))
        #expect(!MuscleSelection(primary: [], secondary: ["chest"]).asksBeforeSaving(categoryName: "Strength"))
    }
}
