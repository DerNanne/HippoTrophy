import Foundation
import Testing
@testable import HippoTrophy

struct ExerciseNamingTests {
    private let catalog = [CatalogExercise(key: "barbell-bench-press", name: "Barbell Bench Press", muscleGroupNames: ["chest"])]

    @Test func aNameIsTakenOnlyByAnotherOwnExercise() {
        let others: [(name: String, catalogKey: String?)] = [("Barbell Bench Press", "barbell-bench-press"), ("Squat", nil)]
        #expect(ExerciseNaming.isFree("barbell bench press ", amongOwn: others))
        #expect(!ExerciseNaming.isFree("SQUAT", amongOwn: others))
    }

    @Test func anOwnExerciseUnderACatalogNameIsTheUsersVersion() {
        #expect(ExerciseNaming.isOwnVersionOfCatalog(name: " barbell bench press", catalogKey: nil, in: catalog))
        #expect(!ExerciseNaming.isOwnVersionOfCatalog(name: "Barbell Bench Press", catalogKey: "barbell-bench-press", in: catalog))
        #expect(!ExerciseNaming.isOwnVersionOfCatalog(name: "Squat", catalogKey: nil, in: catalog))
    }

    private let both: [(identity: ExerciseIdentity, name: String)] = [
        (.catalog("barbell-bench-press"), "Barbell Bench Press"),
        (.own("barbell bench press"), "Barbell Bench Press"),
    ]

    @Test func theIdentityIsFoundBeforeAnyName() {
        #expect(ExerciseNaming.match(identity: .catalog("barbell-bench-press"), name: "Bankdrücken", among: both) == 0)
        #expect(ExerciseNaming.match(identity: .own("barbell bench press"), name: "x", among: both) == 1)
    }

    /// An own entry finds the user's own exercise before the catalog's of the
    /// same name; one with a key this device lacks finds a catalog exercise.
    @Test func aNameLeadsToTheAskersKindFirst() {
        #expect(ExerciseNaming.match(identity: .own("barbell bench press "), name: "Barbell Bench Press", among: both.reversed()) == 0)
        #expect(ExerciseNaming.match(identity: .catalog("unknown"), name: "Barbell Bench Press", among: both.reversed()) == 1)
    }

    /// Files from before the catalog name only the exercise: with no own one
    /// of that name, the catalog's is meant.
    @Test func aNameWithNoOwnExerciseLeadsToTheCatalog() {
        let onlyCatalog = [both[0]]
        #expect(ExerciseNaming.match(identity: .own("barbell bench press"), name: "Barbell Bench Press", among: onlyCatalog) == 0)
        #expect(ExerciseNaming.match(identity: .own("squat"), name: "Squat", among: onlyCatalog) == nil)
    }
}
