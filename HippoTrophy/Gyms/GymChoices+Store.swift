import Foundation
import SwiftData

extension GymChoices {
    /// A new gym. Not saved: the caller saves, and says what failed.
    @discardableResult
    @MainActor
    static func addGym(named name: String, in context: ModelContext) -> Gym {
        let gym = Gym(name: name)
        context.insert(gym)
        return gym
    }

    /// A new machine, standing in `gym` when there is one. Not saved.
    @discardableResult
    @MainActor
    static func addMachine(named name: String, at gym: Gym?, in context: ModelContext) -> Machine {
        addMachine(named: name, standingIn: gym.map { [$0] } ?? [], in: context)
    }

    /// A new machine, standing in each of `gyms`, or in none. Not saved.
    @discardableResult
    @MainActor
    static func addMachine(named name: String, standingIn gyms: [Gym], in context: ModelContext) -> Machine {
        let machine = Machine(name: name)
        context.insert(machine)
        machine.gyms.append(contentsOf: gyms)
        return machine
    }

    /// Puts `entry` at `machine`, or at none. A machine picked in a workout
    /// at a gym it was not in stands there from then on: it was just used
    /// there. Not saved.
    @MainActor
    static func pick(_ machine: Machine?, for entry: ExerciseEntry) {
        entry.machine = machine
        if let machine, let gym = entry.session?.gym, !machine.gyms.contains(where: { $0.id == gym.id }) {
            machine.gyms.append(gym)
        }
    }
}
