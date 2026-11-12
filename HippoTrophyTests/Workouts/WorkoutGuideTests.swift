import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

@MainActor
struct WorkoutGuideTests {
    @Test func theCurrentSetIsTheFirstOpenOne() {
        #expect(WorkoutGuide.current(done: [false, false]) == 0)
        #expect(WorkoutGuide.current(done: [true, false, false]) == 1)
    }

    /// A set passed over does not hold the guide back: it goes on after the
    /// last set done, and comes back for the one passed over at the end.
    @Test func aSetPassedOverWaitsUntilTheEnd() {
        #expect(WorkoutGuide.current(done: [false, true, false]) == 2)
        #expect(WorkoutGuide.current(done: [false, true, true]) == 0)
    }

    @Test func aWorkoutAllDoneHasNoCurrentSet() {
        #expect(WorkoutGuide.current(done: [true, true]) == nil)
        #expect(WorkoutGuide.current(done: []) == nil)
    }

    @Test func afterASetComesTheNextOpenOne() {
        #expect(WorkoutGuide.next(after: 0, done: [true, false, false]) == 1)
        #expect(WorkoutGuide.next(after: 1, done: [true, true, true, false]) == 3)
        #expect(WorkoutGuide.next(after: 2, done: [false, true, true]) == 0)
        #expect(WorkoutGuide.next(after: 1, done: [true, true]) == nil)
    }

    @Test func nextGoesFromFieldToFieldAndStopsAtTheLast() {
        #expect(WorkoutGuide.field(after: "kg", in: ["kg", "reps"]) == "reps")
        #expect(WorkoutGuide.field(after: "reps", in: ["kg", "reps"]) == nil)
        #expect(WorkoutGuide.field(after: "time", in: ["kg", "reps"]) == nil)
    }

    /// Exercise after exercise, and a superset's sets in its shared order.
    @Test func theOrderIsTheOrderSetsAreTrainedIn() throws {
        let context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let session = WorkoutSession()
        context.insert(session)
        let supersetID = UUID()
        let squat = ExerciseEntry(name: "Squat", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        let bench = ExerciseEntry(name: "Bench", orderIndex: 1, definitionID: UUID(), supersetID: supersetID, effortScale: .off, session: session)
        let row = ExerciseEntry(name: "Row", orderIndex: 2, definitionID: UUID(), supersetID: supersetID, effortScale: .off, session: session)
        for entry in [row, squat, bench] { context.insert(entry) }
        for _ in 0..<2 { squat.addSet(on: .both, definition: nil, in: context) }
        let pair = try #require(SupersetPair([bench, row]))
        for _ in 0..<2 {
            pair.addSet(to: bench, definition: nil, in: context)
            pair.addSet(to: row, definition: nil, in: context)
        }

        let order = WorkoutGuide.order(of: [row, squat, bench]).map { "\($0.exercise?.name ?? "")\($0.setNumber)" }
        #expect(order == ["Squat1", "Squat2", "Bench1", "Row1", "Bench2", "Row2"])
    }
}
