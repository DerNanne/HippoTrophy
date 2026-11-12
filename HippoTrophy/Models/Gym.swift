import Foundation
import SwiftData

/// A gym the user trains at, picked for a workout. Optional throughout: a
/// workout without one is one where it was not said. Added in `SchemaV13`.
///
/// Named like an exercise, and told apart by `name.exerciseKey`: there is one
/// gym of a name.
@Model
final class Gym {
    var id: UUID
    var name: String
    /// The machines standing in it. A machine of a kind is in a gym once; the
    /// same kind can stand in several gyms.
    @Relationship(deleteRule: .nullify, inverse: \Machine.gyms)
    var machines: [Machine] = []
    /// The workouts trained here. Deleting the gym leaves them, without it.
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.gym)
    var workouts: [WorkoutSession] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
    }

    var sortedMachines: [Machine] {
        machines.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A machine an exercise was done at — one chest press of several — picked
/// for an exercise in a workout. The exercise stays one exercise wherever and
/// on whatever it was done; the machine only says on which. Added in
/// `SchemaV13`.
@Model
final class Machine {
    var id: UUID
    var name: String
    var gyms: [Gym] = []
    /// The exercises in workouts done at it. Deleting the machine leaves
    /// them, without it.
    @Relationship(deleteRule: .nullify, inverse: \ExerciseEntry.machine)
    var entries: [ExerciseEntry] = []
    /// The picture the user gave it, to tell it apart from others of its
    /// kind. Added in `SchemaV17`, nil for everything before.
    @Relationship(deleteRule: .cascade, inverse: \MachinePhoto.machine)
    var photo: MachinePhoto?

    init(name: String) {
        self.id = UUID()
        self.name = name
    }

    var sortedGyms: [Gym] {
        gyms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
