import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// "Copy Workout" on the start screen: everything logged comes along as a
/// starting point, on the new date, and nothing is shared with the original.
@MainActor
struct WorkoutSessionCopyTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func copiesEntriesSetsAndValuesOnTheNewDate() throws {
        let context = try context()
        let original = WorkoutSession(name: "Push", date: .distantPast, notes: "felt strong")
        context.insert(original)
        let bench = ExerciseEntry(name: "Bench", notes: "shoulder pinched", instructions: "3 s down, wide grip", orderIndex: 0, definitionID: UUID(), effortScale: .levels, session: original)
        bench.unilateralMode = .perSide
        context.insert(bench)
        let set = SetEntry(setNumber: 1, sideRawValue: SetSide.left.rawValue, effortValue: SetEffort.level(.hard).storedValue, exercise: bench)
        context.insert(set)
        context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: 60, set: set))
        context.insert(FieldValue(fieldKey: "f1", label: "Grip", typeRawValue: "text", orderIndex: 1, textValue: "wide", set: set))

        let gym = GymChoices.addGym(named: "Downtown Gym", in: context)
        let machine = GymChoices.addMachine(named: "Chest Press", at: gym, in: context)
        original.gym = gym
        bench.machine = machine

        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let copy = original.copy(dated: date)
        context.insert(copy)
        try context.save()

        #expect(copy.id != original.id)
        #expect(copy.date == date)
        #expect(copy.name == "Push")
        #expect(copy.notes == "felt strong")
        let entry = try #require(copy.exercises.first)
        #expect(entry.id != bench.id)
        #expect(entry.name == "Bench")
        // The plan comes along; what happened last time stays there.
        #expect(entry.instructions == "3 s down, wide grip")
        #expect(entry.notes.isEmpty)
        #expect(entry.definitionID == bench.definitionID)
        // Where it is done is part of the plan, like the instructions.
        #expect(copy.gym?.id == gym.id)
        #expect(entry.machine?.id == machine.id)
        #expect(entry.unilateralMode == .perSide)
        #expect(entry.effortScale == .levels)
        let copiedSet = try #require(entry.sets.first)
        #expect(copiedSet.side == .left)
        #expect(copiedSet.effort == .level(.hard))
        #expect(copiedSet.sortedValues.map(\.numberValue) == [60, nil])
        #expect(copiedSet.sortedValues.map(\.textValue) == [nil, "wide"])
        #expect(original.exercises.first?.sets.count == 1)
    }

    @Test func aSupersetStaysPairedUnderAnIdOfItsOwn() throws {
        let context = try context()
        let original = WorkoutSession()
        context.insert(original)
        let pair = UUID()
        let names = ["Curl", "Pushdown", "Plank"]
        for (index, name) in names.enumerated() {
            context.insert(ExerciseEntry(name: name, orderIndex: index, definitionID: UUID(), supersetID: index < 2 ? pair : nil, effortScale: .off, session: original))
        }

        let copy = original.copy(dated: .now)
        context.insert(copy)
        let entries = copy.exercises.sorted { $0.orderIndex < $1.orderIndex }

        #expect(entries.map(\.name) == names)
        let copiedPair = try #require(entries[0].supersetID)
        #expect(entries[1].supersetID == copiedPair)
        #expect(copiedPair != pair)
        #expect(entries[2].supersetID == nil)
    }
}
