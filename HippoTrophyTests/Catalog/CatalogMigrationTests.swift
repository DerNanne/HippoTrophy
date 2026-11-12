import Foundation
import Testing
@testable import HippoTrophy

@MainActor
struct CatalogMigrationTests {
    private func plain(_ name: String) -> ExerciseRecord {
        ExerciseRecord(
            name: name, category: "Strength", muscleGroupNames: [], tracksSets: true, sides: "either",
            fields: [FieldRecord(key: "weight", label: "Weight", type: "weight"), FieldRecord(key: "reps", label: "Reps", type: "reps")]
        )
    }

    private let bench = ExerciseRecord(
        name: "Barbell Bench Press", category: "Strength", muscleGroupNames: ["chest"], tracksSets: true, sides: "either",
        fields: [FieldRecord(key: "weight", label: "Weight", type: "weight"), FieldRecord(key: "reps", label: "Reps", type: "reps")]
    )

    @Test func weightAndRepsLandOnWeightAndReps() throws {
        let mapping = try #require(CatalogMigration.mapping(from: plain("Bankdrücken"), into: bench))
        #expect(mapping.destinations == ["weight": .field(targetKey: "weight"), "reps": .field(targetKey: "reps")])
    }

    /// Titles the user wrote in their own language still find their field,
    /// by kind.
    @Test func aFieldFindsOneOfItsKindWhateverItIsCalled() throws {
        var own = plain("Bankdrücken")
        own.fields = [FieldRecord(key: "f1", label: "Gewicht", type: "weight"), FieldRecord(key: "f2", label: "Wdh", type: "reps")]
        let mapping = try #require(CatalogMigration.mapping(from: own, into: bench))
        #expect(mapping.destinations == ["f1": .field(targetKey: "weight"), "f2": .field(targetKey: "reps")])
    }

    @Test func onlyRepsIsFine() {
        var own = plain("Push-ups")
        own.fields = [FieldRecord(key: "reps", label: "Reps", type: "reps")]
        #expect(CatalogMigration.mapping(from: own, into: bench) != nil)
    }

    /// A catalog exercise keeps its fields, so a field without a counterpart
    /// makes the move impossible rather than adding one or dropping values.
    @Test func aFieldWithoutACounterpartRulesTheMoveOut() {
        var own = plain("Bench with tempo")
        own.fields.append(FieldRecord(key: "f3", label: "Tempo", type: "text"))
        #expect(CatalogMigration.mapping(from: own, into: bench) == nil)
    }

    @Test func twoWeightFieldsCannotShareOne() {
        var own = plain("Bench")
        own.fields.append(FieldRecord(key: "f3", label: "Extra", type: "weight"))
        #expect(CatalogMigration.mapping(from: own, into: bench) == nil)
    }

    @Test func onceAWorkoutCannotMoveToSets() {
        var own = plain("Bench")
        own.tracksSets = false
        #expect(CatalogMigration.mapping(from: own, into: bench) == nil)
    }

    @Test func targetsSharingMoreWordsComeFirst() {
        let catalog = [plain("Dumbbell Curl"), plain("Barbell Row"), plain("Barbell Bench Press"), plain("Dumbbell Bench Press")]
        let targets = CatalogMigration.targets(for: plain("bench press barbell"), among: catalog)
        #expect(targets.map(\.name) == ["Barbell Bench Press", "Dumbbell Bench Press", "Barbell Row", "Dumbbell Curl"])
    }

    /// No word in common is no reason not to ask: the user can search, or
    /// keep it. The test backup's "ÜbungXY" brought no review at all.
    @Test func anExerciseThatCanMoveIsOpenWithoutASuggestion() {
        let catalog = [plain("Barbell Bench Press")]
        #expect(CatalogMigration.suggestions(for: plain("ÜbungXY"), among: catalog).isEmpty)
        #expect(CatalogMigration.isOpen(plain("ÜbungXY"), among: catalog))
    }

    @Test func anExerciseThatCanMoveNowhereIsNotOpen() {
        var tempo = plain("Bench with tempo")
        tempo.fields.append(FieldRecord(key: "f3", label: "Tempo", type: "text"))
        var once = plain("Plank")
        once.tracksSets = false
        #expect(!CatalogMigration.isOpen(tempo, among: [bench]))
        #expect(!CatalogMigration.isOpen(once, among: [bench]))
    }

    @Test func suggestionsShareAWord() {
        let catalog = [plain("Dumbbell Curl"), plain("Barbell Bench Press"), plain("Push-Up")]
        #expect(CatalogMigration.suggestions(for: plain("Bench"), among: catalog).map(\.name) == ["Barbell Bench Press"])
        #expect(CatalogMigration.suggestions(for: plain("push ups"), among: catalog).map(\.name) == ["Push-Up"])
        #expect(CatalogMigration.suggestions(for: plain("Bankdrücken"), among: catalog).isEmpty)
    }

    @Test func keptIdsRoundTrip() {
        let ids: Set<UUID> = [UUID(), UUID()]
        var kept = KeptOwnExercises(stored: "")
        kept.ids = ids
        #expect(KeptOwnExercises(stored: kept.stored).ids == ids)
        #expect(KeptOwnExercises(stored: "garbage,").ids.isEmpty)
    }
}

struct CatalogReviewPromptTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func prompt(pending: Int = 2, moved: Int = 0, dontShowAgain: Bool = false, hoursAgo: Double? = nil) -> CatalogReviewPrompt {
        CatalogReviewPrompt(
            pending: pending, moved: moved, dontShowAgain: dontShowAgain,
            lastShown: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) }
        )
    }

    @Test func firstTimeWithSomethingOpenItShows() {
        #expect(prompt().shouldShow(at: now))
    }

    @Test func nothingOpenNothingShown() {
        #expect(!prompt(pending: 0).shouldShow(at: now))
    }

    /// Back in the app mid-workout is not the moment.
    @Test func notAgainWithinThreeHours() {
        #expect(!prompt(hoursAgo: 0.5).shouldShow(at: now))
        #expect(!prompt(hoursAgo: 2.9).shouldShow(at: now))
        #expect(prompt(hoursAgo: 3).shouldShow(at: now))
    }

    @Test func dontShowAgainIsFinal() {
        #expect(!prompt(dontShowAgain: true).shouldShow(at: now))
    }

    /// Three moved and the review was done; the rest are theirs.
    @Test func itStopsOnceEnoughWereMoved() {
        #expect(prompt(moved: 2).shouldShow(at: now))
        #expect(!prompt(moved: 3).shouldShow(at: now))
    }
}
