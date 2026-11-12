import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// How a workout's exercises are grouped for display: a superset's members
/// stay together wherever they sit, and everything else is its own group of
/// one.
@MainActor
struct ExerciseGroupingTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func entry(_ name: String, order: Int, supersetID: UUID? = nil, in context: ModelContext) -> ExerciseEntry {
        let entry = ExerciseEntry(name: name, orderIndex: order, definitionID: UUID(), supersetID: supersetID, effortScale: .off)
        context.insert(entry)
        return entry
    }

    @Test func exercisesWithNoSupersetAreEachTheirOwnGroup() throws {
        let context = try context()
        let a = entry("Squat", order: 0, in: context)
        let b = entry("Bench", order: 1, in: context)

        let groups = ExerciseGrouping.groups([a, b])
        #expect(groups.map { $0.map(\.name) } == [["Squat"], ["Bench"]])
    }

    @Test func adjacentSupersetMembersGroupTogether() throws {
        let context = try context()
        let supersetID = UUID()
        let a = entry("Curl", order: 0, supersetID: supersetID, in: context)
        let b = entry("Pushdown", order: 1, supersetID: supersetID, in: context)
        let c = entry("Squat", order: 2, in: context)

        let groups = ExerciseGrouping.groups([a, b, c])
        #expect(groups.map { $0.map(\.name) } == [["Curl", "Pushdown"], ["Squat"]])
    }

    /// A superset's pairing survives something else ending up between its two
    /// members in the stored order — grouping goes by id, not by adjacency.
    @Test func nonAdjacentSupersetMembersStillGroupTogether() throws {
        let context = try context()
        let supersetID = UUID()
        let a = entry("Curl", order: 0, supersetID: supersetID, in: context)
        let between = entry("Squat", order: 1, in: context)
        let b = entry("Pushdown", order: 2, supersetID: supersetID, in: context)

        let groups = ExerciseGrouping.groups([a, between, b])
        #expect(groups.map { $0.map(\.name) } == [["Curl", "Pushdown"], ["Squat"]])
    }

    @Test func twoDifferentSupersetsStayApart() throws {
        let context = try context()
        let first = UUID()
        let second = UUID()
        let a = entry("Curl", order: 0, supersetID: first, in: context)
        let b = entry("Squat", order: 1, supersetID: second, in: context)
        let c = entry("Pushdown", order: 2, supersetID: first, in: context)
        let d = entry("Lunge", order: 3, supersetID: second, in: context)

        let groups = ExerciseGrouping.groups([a, b, c, d])
        #expect(groups.map { $0.map(\.name) } == [["Curl", "Pushdown"], ["Squat", "Lunge"]])
    }

    @Test func anEmptyWorkoutHasNoGroups() {
        #expect(ExerciseGrouping.groups([ExerciseEntry]()).isEmpty)
    }

    /// The reorder sheet shows a superset as one row; dragging it to the top
    /// brings both members there, in their order, and nothing in between.
    @Test func aSupersetMovesAsOneRow() throws {
        let context = try context()
        let superset = UUID()
        let split = entry("Split Squat", order: 0, in: context)
        let bench = entry("Bench", order: 1, supersetID: superset, in: context)
        let fly = entry("Cable Fly", order: 2, supersetID: superset, in: context)
        let carry = entry("Carry", order: 3, in: context)

        let order = ExerciseGrouping.reordered([split, bench, fly, carry], movingGroups: [1], to: 0)
        #expect(order.map(\.name) == ["Bench", "Cable Fly", "Split Squat", "Carry"])
    }

    /// Moving down counts the destination before the move, as a list's drag
    /// reports it: past the last row is the end.
    @Test func aRowMovedDownLandsWhereItWasDropped() throws {
        let context = try context()
        let superset = UUID()
        let split = entry("Split Squat", order: 0, in: context)
        let bench = entry("Bench", order: 1, supersetID: superset, in: context)
        let fly = entry("Cable Fly", order: 2, supersetID: superset, in: context)
        let carry = entry("Carry", order: 3, in: context)

        #expect(ExerciseGrouping.reordered([split, bench, fly, carry], movingGroups: [0], to: 3).map(\.name)
            == ["Bench", "Cable Fly", "Carry", "Split Squat"])
        #expect(ExerciseGrouping.reordered([split, bench, fly, carry], movingGroups: [0], to: 2).map(\.name)
            == ["Bench", "Cable Fly", "Split Squat", "Carry"])
    }

    /// Members stored apart — an older reorder could split them — come back
    /// together at the first one's place with any move.
    @Test func aSplitSupersetIsJoinedByTheNextMove() throws {
        let context = try context()
        let superset = UUID()
        let fly = entry("Cable Fly", order: 0, supersetID: superset, in: context)
        let split = entry("Split Squat", order: 1, in: context)
        let bench = entry("Bench", order: 2, supersetID: superset, in: context)
        let carry = entry("Carry", order: 3, in: context)

        let order = ExerciseGrouping.reordered([fly, split, bench, carry], movingGroups: [2], to: 0)
        #expect(order.map(\.name) == ["Carry", "Cable Fly", "Bench", "Split Squat"])
    }
}

