import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Whether an entry's exercise logs sets: the definition's to say, and
/// without one, what the entry holds.
@MainActor
struct ExerciseEntryTracksSetsTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(
            try ModelContainer(
                for: Schema(AppSchema.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    private func entry(of definitionID: UUID, sets: Int) -> ExerciseEntry {
        let entry = ExerciseEntry(name: "Rowing Erg", orderIndex: 0, definitionID: definitionID, effortScale: .off, session: nil)
        context.insert(entry)
        for number in 1...sets {
            context.insert(SetEntry(setNumber: number, exercise: entry))
        }
        return entry
    }

    @Test func theDefinitionDecides() {
        let once = ExerciseDefinition(name: "Rowing Erg", orderIndex: 0, tracksSets: false)
        let sets = ExerciseDefinition(name: "Farmer's Carry", orderIndex: 1, tracksSets: true)
        context.insert(once)
        context.insert(sets)

        #expect(!entry(of: once.id, sets: 1).tracksSets(among: [once, sets]))
        #expect(entry(of: sets.id, sets: 1).tracksSets(among: [once, sets]))
    }

    @Test func withoutADefinitionSeveralSetsMeanSets() {
        #expect(!entry(of: UUID(), sets: 1).tracksSets(among: []))
        #expect(entry(of: UUID(), sets: 2).tracksSets(among: []))
    }
}
