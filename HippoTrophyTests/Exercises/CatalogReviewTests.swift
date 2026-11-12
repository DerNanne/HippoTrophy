import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The review's first section and the number on the menu and at launch are one
/// list: a dot that says 2 over a section of 1 stays until someone finds the other.
@MainActor
struct CatalogReviewTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func plain(_ name: String, catalogKey: String? = nil, in context: ModelContext) -> ExerciseDefinition {
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: name, orderIndex: 0, in: context)
        definition.catalogKey = catalogKey
        return definition
    }

    @Test func openIsTheOwnExercisesThatCanMoveWithOrWithoutAWordInCommon() throws {
        let context = try context()
        let catalog = plain("Barbell Bench Press", catalogKey: "barbell-bench-press", in: context)
        let sharesAWord = plain("Bench", in: context)
        let sharesNone = plain("Bankdrücken", in: context)
        let canMoveNowhere = plain("Plank", in: context)
        canMoveNowhere.tracksSets = false

        let open = CatalogReview.open(in: [catalog, sharesAWord, sharesNone, canMoveNowhere], kept: [])
        #expect(open.map(\.name) == ["Bankdrücken", "Bench"])
    }

    @Test func aKeptExerciseIsNoLongerOpen() throws {
        let context = try context()
        let catalog = plain("Barbell Bench Press", catalogKey: "barbell-bench-press", in: context)
        let mine = plain("Bench", in: context)

        #expect(CatalogReview.pendingCount(in: [catalog, mine], kept: []) == 1)
        #expect(CatalogReview.pendingCount(in: [catalog, mine], kept: [mine.id]) == 0)
    }
}
