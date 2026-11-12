import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Set editing in the workout editor: numbers stay 1…n per side, values travel
/// with copies, and switching modes moves sets rather than dropping them.
@MainActor
struct ExerciseEntryEditingTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func entry(in context: ModelContext) -> ExerciseEntry {
        let session = WorkoutSession()
        context.insert(session)
        let entry = ExerciseEntry(name: "Curl", orderIndex: 0, definitionID: UUID(), effortScale: .levels, session: session)
        context.insert(entry)
        return entry
    }

    private func reps(_ set: SetEntry) -> Double? {
        set.sortedValues.first { $0.fieldKey == "reps" }?.numberValue
    }

    @Test func aNewSetGetsTheNextNumberOnItsSideAndAnEmptyValuePerField() throws {
        let context = try context()
        let definition = ExerciseDefinition(name: "Curl", orderIndex: 0)
        context.insert(definition)
        for (index, type) in FieldType.standard.enumerated() {
            let field = FieldDefinition(key: type.standardKey ?? type.rawValue, label: type.displayName, typeRawValue: type.rawValue, orderIndex: index, definition: definition)
            definition.fields.append(field)
            context.insert(field)
        }
        let entry = entry(in: context)

        entry.addSet(on: .left, definition: definition, in: context)
        entry.addSet(on: .right, definition: definition, in: context)
        let second = entry.addSet(on: .left, definition: definition, in: context)

        #expect(second.setNumber == 2)
        #expect(entry.sets(on: .right).map(\.setNumber) == [1])
        #expect(second.sortedValues.map(\.fieldKey) == ["weight", "reps"])
        #expect(second.sortedValues.allSatisfy { $0.isEmpty })
    }

    @Test func withoutADefinitionANewSetTakesTheLastSetsFields() throws {
        let context = try context()
        let entry = entry(in: context)
        let first = entry.addSet(on: .both, definition: nil, in: context)
        context.insert(FieldValue(fieldKey: "f1", label: "Distance", typeRawValue: "number", orderIndex: 0, numberValue: 5, set: first))

        let next = entry.addSet(on: .both, definition: nil, in: context)
        #expect(next.sortedValues.map(\.label) == ["Distance"])
        #expect(next.sortedValues.first?.isEmpty == true)
    }

    @Test func deletingASetClosesTheGap() throws {
        let context = try context()
        let entry = entry(in: context)
        let sets = (0..<3).map { _ in entry.addSet(on: .both, definition: nil, in: context) }

        entry.deleteSet(sets[1], in: context)
        #expect(entry.sets(on: .both).map(\.id) == [sets[0].id, sets[2].id])
        #expect(entry.sets(on: .both).map(\.setNumber) == [1, 2])
    }

    @Test func aCopyLandsRightBehindItsSourceWithItsValues() throws {
        let context = try context()
        let entry = entry(in: context)
        let sets = (0..<2).map { _ in entry.addSet(on: .both, definition: nil, in: context) }
        sets[0].effort = .level(.hard)
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: 8, set: sets[0]))

        let copy = entry.copySet(sets[0], in: context)
        #expect(entry.sets(on: .both).map(\.id) == [sets[0].id, copy.id, sets[1].id])
        #expect(entry.sets(on: .both).map(\.setNumber) == [1, 2, 3])
        #expect(reps(copy) == 8)
        #expect(copy.effort == .level(.hard))
    }

    @Test func movingRenumbersInTheNewOrder() throws {
        let context = try context()
        let entry = entry(in: context)
        let sets = (0..<3).map { _ in entry.addSet(on: .both, definition: nil, in: context) }

        entry.moveSets(on: .both, from: IndexSet(integer: 0), to: 3)
        #expect(entry.sets(on: .both).map(\.id) == [sets[1].id, sets[2].id, sets[0].id])

        entry.moveSets(on: .both, from: IndexSet(integer: 2), to: 0)
        #expect(entry.sets(on: .both).map(\.id) == sets.map(\.id))
        #expect(entry.sets(on: .both).map(\.setNumber) == [1, 2, 3])
    }

    @Test func leavingLeftRightMergesLeftBeforeRight() throws {
        let context = try context()
        let entry = entry(in: context)
        entry.unilateralMode = .perSide
        let right = entry.addSet(on: .right, definition: nil, in: context)
        let left = (0..<2).map { _ in entry.addSet(on: .left, definition: nil, in: context) }
        #expect(entry.holdsBothSides)

        entry.applyMode(.bilateral)
        #expect(entry.sets(on: .both).map(\.id) == [left[0].id, left[1].id, right.id])
        #expect(entry.sets(on: .both).map(\.setNumber) == [1, 2, 3])
        #expect(!entry.holdsBothSides)
    }

    @Test func goingLeftRightMovesEverySetToTheLeft() throws {
        let context = try context()
        let entry = entry(in: context)
        _ = (0..<2).map { _ in entry.addSet(on: .both, definition: nil, in: context) }

        entry.applyMode(.perSide)
        #expect(entry.unilateralMode == .perSide)
        #expect(entry.sets(on: .left).count == 2)
        #expect(entry.sets(on: .both).isEmpty)
    }

    /// A rating does not carry over to another scale, so a switch drops every
    /// one the entry holds — and says beforehand how many.
    @Test func aSwitchDropsEveryRatingAndKeepsTheValues() throws {
        let context = try context()
        let entry = entry(in: context)
        let sets = (0..<3).map { _ in entry.addSet(on: .both, definition: nil, in: context) }
        sets[0].effort = .level(.hard)
        sets[2].effort = .level(.easy)
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 0, numberValue: 8, set: sets[0]))

        #expect(entry.ratingsDiscarded(bySwitchingTo: .rir) == 2)
        entry.switchEffortScale(to: .rir)

        #expect(entry.effortScale == .rir)
        #expect(entry.sets.allSatisfy { $0.effortValue == nil })
        #expect(reps(sets[0]) == 8)
    }

    @Test func switchingOffDropsTheRatingsToo() throws {
        let context = try context()
        let entry = entry(in: context)
        entry.addSet(on: .both, definition: nil, in: context).effort = .level(.normal)

        #expect(entry.ratingsDiscarded(bySwitchingTo: .off) == 1)
        entry.switchEffortScale(to: .off)
        #expect(entry.sets.first?.effortValue == nil)
    }

    @Test func theSameScaleAgainChangesNothing() throws {
        let context = try context()
        let entry = entry(in: context)
        entry.addSet(on: .both, definition: nil, in: context).effort = .level(.hard)

        #expect(entry.ratingsDiscarded(bySwitchingTo: .levels) == 0)
        entry.switchEffortScale(to: .levels)
        #expect(entry.sets.first?.effort == .level(.hard))
    }

    /// Nothing rated, nothing to ask about.
    @Test func unratedSetsAreNothingToDiscard() throws {
        let context = try context()
        let entry = entry(in: context)
        _ = (0..<2).map { _ in entry.addSet(on: .both, definition: nil, in: context) }
        #expect(entry.ratingsDiscarded(bySwitchingTo: .rir) == 0)
    }

    /// Earlier workouts keep how they were rated: the switch is the entry's,
    /// not the exercise's.
    @Test func aSwitchLeavesOtherEntriesOfTheSameExerciseAlone() throws {
        let context = try context()
        let earlier = entry(in: context)
        let today = ExerciseEntry(name: earlier.name, orderIndex: 0, definitionID: earlier.definitionID, effortScale: .levels)
        context.insert(today)
        earlier.addSet(on: .both, definition: nil, in: context).effort = .level(.hard)
        today.addSet(on: .both, definition: nil, in: context).effort = .level(.hard)

        today.switchEffortScale(to: .rir)

        #expect(earlier.effortScale == .levels)
        #expect(earlier.sets.first?.effort == .level(.hard))
    }

    @Test func theWarningCountsInSingularAndPlural() {
        let one = PendingEffortScaleChange(exerciseID: UUID(), scale: .rir, discarded: 1)
        let three = PendingEffortScaleChange(exerciseID: UUID(), scale: .rir, discarded: 3)
        #expect(one.message.hasPrefix("⚠️ The rating of 1 set "))
        #expect(three.message.hasPrefix("⚠️ The ratings of 3 sets "))
    }
}

