import Testing
@testable import HippoTrophy

/// What the question before deleting a workout says goes with it — in the list
/// and when a workout being trained is discarded.
struct WorkoutDeletionTests {
    @Test func anEmptyWorkoutSaysNothingWasLogged() {
        #expect(WorkoutDeletion.message(setCount: 0) == "Nothing was logged in it. This cannot be undone.")
    }

    @Test func oneSetIsSingular() {
        #expect(WorkoutDeletion.message(setCount: 1) == "1 logged set is deleted with it. This cannot be undone.")
    }

    @Test func severalSetsAreCounted() {
        #expect(WorkoutDeletion.message(setCount: 7) == "7 logged sets are deleted with it. This cannot be undone.")
    }

    @Test func severalWorkoutsAreThem() {
        #expect(WorkoutDeletion.message(setCount: 4, workoutCount: 2) == "4 logged sets are deleted with them. This cannot be undone.")
        #expect(WorkoutDeletion.message(setCount: 0, workoutCount: 3) == "Nothing was logged in them. This cannot be undone.")
    }
}
