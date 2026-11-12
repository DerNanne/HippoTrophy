import Testing
@testable import HippoTrophy

/// Where an entry goes whose mode no longer fits how its catalog exercise is
/// trained.
struct SideMigrationTests {
    private let legPress = CatalogExercise(key: "leg-press", name: "Leg Press", muscleGroupNames: ["quads", "glutes"])
    private let legPressOne = CatalogExercise(
        key: "leg-press-unilateral", name: "Leg Press (Unilateral)", muscleGroupNames: ["quads", "glutes"],
        sides: .one, unilateralOf: "leg-press"
    )
    private let chestPress = CatalogExercise(key: "chest-press-machine", name: "Chest Press Machine", muscleGroupNames: ["chest", "triceps"])
    private let splitSquat = CatalogExercise(key: "bulgarian-split-squat", name: "Bulgarian Split Squat", muscleGroupNames: ["quads", "glutes"], sides: .one)

    private var catalog: [CatalogExercise] { [legPress, legPressOne, chestPress, splitSquat] }

    private func move(_ mode: UnilateralMode, _ key: String?) -> SideMigration.Move? {
        SideMigration.move(mode: mode, exerciseKey: key, catalog: catalog)
    }

    @Test func aOneSidedEntryOfATwoSidedExerciseGoesToItsOneSidedForm() {
        #expect(move(.perSide, "leg-press") == .catalog(key: "leg-press-unilateral"))
        #expect(move(.oneSided, "leg-press") == .catalog(key: "leg-press-unilateral"))
    }

    /// Without a one-sided form in the catalog, it goes to the user's own one
    /// under the name the catalog would give it, so it is adopted on the day
    /// the catalog has it.
    @Test func withoutOneInTheCatalogItGoesToAnOwnOneSidedForm() {
        #expect(move(.perSide, "chest-press-machine") == .own(name: "Chest Press Machine (Unilateral)", muscleGroupNames: ["chest", "triceps"]))
    }

    @Test func aTwoSidedEntryOfAOneSidedExerciseBecomesOneSided() {
        #expect(move(.bilateral, "bulgarian-split-squat") == .mode(.oneSided))
    }

    @Test func entriesThatFitStay() {
        #expect(move(.bilateral, "leg-press") == nil)
        #expect(move(.perSide, "leg-press-unilateral") == nil)
        #expect(move(.oneSided, "bulgarian-split-squat") == nil)
    }

    /// The user's own exercises are as the user logged them.
    @Test func ownExercisesAreLeftAlone() {
        #expect(move(.perSide, nil) == nil)
        #expect(move(.perSide, "a-key-the-catalog-dropped") == nil)
    }
}
