import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// A set in the reorder list says which it is and what is in it, so two sets
/// can be told apart before one is dragged past the other.
@MainActor
struct SetReorderRowTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func set(in context: ModelContext, weight: Double?, angle: Double?) -> SetEntry {
        let session = WorkoutSession()
        context.insert(session)
        let entry = ExerciseEntry(name: "Isometric Leg Extension", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        let set = SetEntry(setNumber: 2, exercise: entry)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: weight, set: set))
        context.insert(FieldValue(fieldKey: "f2", label: "Knee Angle", typeRawValue: "number", orderIndex: 2, numberValue: angle, set: set))
        context.insert(FieldValue(fieldKey: "f1", label: "Note", typeRawValue: "text", orderIndex: 1, set: set))
        return set
    }

    @Test func theValuesFollowTheFieldsAndLeaveTheEmptyOnesOut() throws {
        let context = try context()
        let set = set(in: context, weight: 40, angle: 60)

        let row = SetReorderRow(set, name: "Set 2", unit: .kilograms)

        #expect(row.id == set.id)
        #expect(row.title == "Set 2")
        #expect(row.values == "\(WeightUnit.kilograms.formatted(kilograms: 40)) · 60")
    }

    @Test func aSetWithNothingInItSaysSo() throws {
        let context = try context()
        let row = SetReorderRow(set(in: context, weight: nil, angle: nil), name: "Left · Set 2", unit: .kilograms)
        #expect(row.values == "Nothing logged")
    }
}
