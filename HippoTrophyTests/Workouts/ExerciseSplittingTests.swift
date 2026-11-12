import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Turning "Track Sets" off must not lose a value: an entry with several sets
/// becomes several entries with one set each, in order, in place.
@MainActor
struct ExerciseSplittingTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func eachSetBecomesAnEntryBehindTheFirst() throws {
        let context = try context()
        let session = WorkoutSession()
        context.insert(session)
        let definitionID = UUID()
        let before = ExerciseEntry(name: "Warm-up", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        let carry = ExerciseEntry(name: "Farmer Carry", notes: "heavy", orderIndex: 1, definitionID: definitionID, effortScale: .levels, session: session)
        let after = ExerciseEntry(name: "Squat", orderIndex: 2, definitionID: UUID(), effortScale: .off, session: session)
        for entry in [before, carry, after] { context.insert(entry) }
        for number in 1...3 {
            let set = SetEntry(setNumber: number, effortValue: number == 2 ? SetEffort.level(.hard).storedValue : nil, exercise: carry)
            context.insert(set)
            context.insert(FieldValue(fieldKey: "f1", label: "Distance", typeRawValue: "number", orderIndex: 0, numberValue: Double(number * 10), set: set))
        }

        ExerciseSplitting.splitIntoSingleSets([carry], in: context)
        try context.save()

        let ordered = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        #expect(ordered.map(\.name) == ["Warm-up", "Farmer Carry", "Farmer Carry", "Farmer Carry", "Squat"])
        #expect(ordered.map(\.orderIndex) == [0, 1, 2, 3, 4])
        let carries = ordered.filter { $0.definitionID == definitionID }
        #expect(carries.allSatisfy { $0.sets.count == 1 && $0.sets.first?.setNumber == 1 })
        #expect(carries.map { $0.sets.first?.values.first?.numberValue } == [10, 20, 30])
        #expect(carries.allSatisfy { $0.effortScale == .levels })
        #expect(carries.map { $0.sets.first?.effort } == [nil, .level(.hard), nil])
        #expect(carries.map(\.notes) == ["heavy", "", ""])
    }

    @Test func anEntryWithOneSetIsLeftAlone() throws {
        let context = try context()
        let session = WorkoutSession()
        context.insert(session)
        let entry = ExerciseEntry(name: "Rowing", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        context.insert(SetEntry(setNumber: 1, exercise: entry))

        #expect(ExerciseSplitting.entriesWithSeveralSets([entry]).isEmpty)
        ExerciseSplitting.splitIntoSingleSets([entry], in: context)
        #expect(session.exercises.count == 1)
    }
}
