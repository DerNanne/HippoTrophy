import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// A superset's sets in the store: one shared order, with each exercise's set
/// numbers always counted from it.
@MainActor
struct SupersetPairTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// Bench (A) and Row (B), each with `aSets`/`bSets` sets logged before
    /// they were paired.
    private func pair(aSets: Int = 0, bSets: Int = 0, in context: ModelContext) throws -> SupersetPair {
        let session = WorkoutSession()
        context.insert(session)
        let supersetID = UUID()
        let bench = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), supersetID: supersetID, effortScale: .off, session: session)
        let row = ExerciseEntry(name: "Row", orderIndex: 1, definitionID: UUID(), supersetID: supersetID, effortScale: .off, session: session)
        // Inserted B first, to show A is decided by order, not by insertion.
        for entry in [row, bench] { context.insert(entry) }
        for _ in 0..<aSets { bench.addSet(on: .both, definition: nil, in: context) }
        for _ in 0..<bSets { row.addSet(on: .both, definition: nil, in: context) }
        return try #require(SupersetPair([row, bench]))
    }

    private func sequence(_ pair: SupersetPair) -> String {
        pair.orderedSets.map { "\(pair.member(of: $0) == .a ? "A" : "B")\($0.setNumber)" }.joined(separator: " ")
    }

    @Test func aIsTheExerciseHigherInTheWorkout() throws {
        let pair = try pair(in: try context())
        #expect(pair.a.name == "Bench")
        #expect(pair.b.name == "Row")
    }

    @Test func pairingInterleavesSetsAlreadyLogged() throws {
        let pair = try pair(aSets: 3, bSets: 5, in: try context())
        pair.interleaveExisting()
        #expect(sequence(pair) == "A1 B1 A2 B2 A3 B3 B4 B5")
        #expect(pair.orderedSets.map(\.supersetPosition) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func aNewSetGoesToTheEndOfTheOrder() throws {
        let context = try context()
        let pair = try pair(aSets: 1, bSets: 1, in: context)
        pair.interleaveExisting()
        pair.addSet(to: pair.a, definition: nil, in: context)
        pair.addSet(to: pair.a, definition: nil, in: context)
        #expect(sequence(pair) == "A1 B1 A2 A3")
    }

    @Test func movingASetAcrossRenumbersBothExercises() throws {
        let pair = try pair(aSets: 2, bSets: 2, in: try context())
        pair.interleaveExisting()                                   // A1 B1 A2 B2
        pair.moveSets(from: IndexSet(integer: 3), to: 1)            // B2 above B1
        #expect(sequence(pair) == "A1 B1 B2 A2")
        #expect(pair.orderedSets.map(\.supersetPosition) == [1, 2, 3, 4])
    }

    @Test func deletingASetClosesTheGapInTheOrderAndInItsNumbers() throws {
        let context = try context()
        let pair = try pair(aSets: 3, bSets: 2, in: context)
        pair.interleaveExisting()                                   // A1 B1 A2 B2 A3
        let a2 = pair.orderedSets[2]
        pair.deleteSet(a2, in: context)
        #expect(sequence(pair) == "A1 B1 B2 A2")
        #expect(pair.orderedSets.map(\.supersetPosition) == [1, 2, 3, 4])
    }

    @Test func aCopyLandsRightBehindItsSource() throws {
        let context = try context()
        let pair = try pair(aSets: 2, bSets: 2, in: context)
        pair.interleaveExisting()                                   // A1 B1 A2 B2
        let b1 = pair.orderedSets[1]
        let copy = try #require(pair.copySet(b1, in: context))
        #expect(sequence(pair) == "A1 B1 B2 A2 B3")
        #expect(pair.orderedSets[2].id == copy.id)
    }

    @Test func dissolvingKeepsNumbersAndDropsPositions() throws {
        let pair = try pair(aSets: 2, bSets: 1, in: try context())
        pair.interleaveExisting()
        SupersetPair.dissolve(pair.a)
        #expect(pair.a.supersetID == nil)
        #expect(pair.a.sortedSets.map(\.setNumber) == [1, 2])
        #expect(pair.a.sets.allSatisfy { $0.supersetPosition == nil })
    }

    @Test func onlyTwoEntriesMakeAPair() throws {
        let context = try context()
        let session = WorkoutSession()
        context.insert(session)
        let entries = (0..<3).map { ExerciseEntry(name: "E\($0)", orderIndex: $0, definitionID: UUID(), effortScale: .off, session: session) }
        #expect(SupersetPair(Array(entries.prefix(1))) == nil)
        #expect(SupersetPair(entries) == nil)
    }

    @Test func setsWithoutPositionsReadAsRoundsUntilTheFirstChange() throws {
        let context = try context()
        let pair = try pair(aSets: 2, bSets: 1, in: context)
        #expect(sequence(pair) == "A1 B1 A2")
        #expect(pair.orderedSets.allSatisfy { $0.supersetPosition == nil })

        pair.addSet(to: pair.b, definition: nil, in: context)
        #expect(sequence(pair) == "A1 B1 A2 B2")
        #expect(pair.orderedSets.map(\.supersetPosition) == [1, 2, 3, 4])
    }
}
