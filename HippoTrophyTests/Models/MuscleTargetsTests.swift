import Foundation
import Testing
@testable import HippoTrophy

struct MuscleTargetsTests {
    @Test func aMainMuscleCountsInFullASecondaryOneHalf() {
        let squat = MuscleTargets(primary: [.quads, .glutes], secondary: [.adductors])
        #expect(squat.share(for: .quads) == 1)
        #expect(squat.share(for: .adductors) == 0.5)
        #expect(squat.share(for: .chest) == 0)
        #expect(squat.all == [.quads, .glutes, .adductors])
    }

    /// Picked as both, a muscle is a main one: it counts once, in full.
    @Test func aMuscleNamedTwiceIsAMainOne() {
        let targets = MuscleTargets(primary: [.chest], secondary: [.chest, .triceps])
        #expect(targets.secondary == [.triceps])
        #expect(targets.share(for: .chest) == 1)
    }

    @Test func theDefinitionLeavesOutASecondaryMuscleThatIsAlsoMain() {
        let definition = ExerciseDefinition(name: "Dip", orderIndex: 0, muscleGroupNames: ["chest"], secondaryMuscleGroupNames: ["chest", "triceps", "nonsense"])
        #expect(definition.secondaryMuscleGroups == [.triceps])
    }
}
