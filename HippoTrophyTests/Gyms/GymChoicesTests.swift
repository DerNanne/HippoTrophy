import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// What the gym and machine menus offer, and the machine an exercise starts
/// with.
@MainActor
struct GymChoicesTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func aNewNameIsTrimmedAndNeitherEmptyNorTaken() {
        #expect(GymChoices.newName("  Forge Fitness ", among: ["Home"]) == "Forge Fitness")
        #expect(GymChoices.newName("   ", among: []) == nil)
        #expect(GymChoices.newName("home", among: ["Home"]) == nil)
    }

    /// What the field says when a name is not taken, so that leaving it does
    /// not silently bring the old one back.
    @Test func aRefusedNameSaysWhy() {
        #expect(GymChoices.refusal(of: "  ", among: ["Home"], kind: "gym") == "A gym needs a name.")
        #expect(GymChoices.refusal(of: "home ", among: ["Home"], kind: "gym") == "There is a gym of this name already.")
        #expect(GymChoices.refusal(of: "Chest Press", among: ["chest press"], kind: "machine") == "There is a machine of this name already.")
        #expect(GymChoices.refusal(of: "Forge Fitness", among: ["Home"], kind: "gym") == nil)
    }

    @Test func aNameIsTakenWhateverItsSpelling() {
        #expect(GymChoices.isTaken("  chest press ", among: ["Chest Press"]))
        #expect(!GymChoices.isTaken("Chest Press 2", among: ["Chest Press"]))
        #expect(!GymChoices.isTaken("   ", among: ["Chest Press"]))
    }

    /// Standing in several gyms, or in none: both are a machine.
    @Test func aNewMachineStandsInTheGymsItWasGiven() {
        let downtown = GymChoices.addGym(named: "Downtown Gym", in: context)
        let home = GymChoices.addGym(named: "Home", in: context)

        let everywhere = GymChoices.addMachine(named: "Chest Press", standingIn: [downtown, home], in: context)
        #expect(everywhere.sortedGyms.map(\.name) == ["Downtown Gym", "Home"])
        #expect(downtown.machines.map(\.id) == [everywhere.id])
        #expect(home.machines.map(\.id) == [everywhere.id])

        let nowhere = GymChoices.addMachine(named: "Hack Squat", standingIn: [], in: context)
        #expect(nowhere.gyms.isEmpty)
    }

    @Test func theMachinesStandingInTheGymComeFirst() {
        let gym = GymChoices.addGym(named: "Downtown Gym", in: context)
        let press = GymChoices.addMachine(named: "Chest Press", at: gym, in: context)
        let extensionMachine = GymChoices.addMachine(named: "Leg Extension", at: gym, in: context)
        let hack = GymChoices.addMachine(named: "Hack Squat", at: nil, in: context)

        let choices = GymChoices.machines(at: gym, among: [hack, press, extensionMachine])
        #expect(choices.here.map(\.name) == ["Chest Press", "Leg Extension"])
        #expect(choices.elsewhere.map(\.name) == ["Hack Squat"])
    }

    @Test func withoutAGymEveryMachineIsOffered() {
        let press = GymChoices.addMachine(named: "Chest Press", at: nil, in: context)
        let hack = GymChoices.addMachine(named: "Hack Squat", at: nil, in: context)

        let choices = GymChoices.machines(at: nil, among: [hack, press])
        #expect(choices.here.map(\.name) == ["Chest Press", "Hack Squat"])
        #expect(choices.elsewhere.isEmpty)
    }

    /// The machine it was last done at in that gym — not the last one
    /// anywhere, which may not be in the room.
    @Test func anExerciseStartsAtTheMachineItWasLastDoneAtInThatGym() throws {
        let downtown = GymChoices.addGym(named: "Downtown Gym", in: context)
        let home = GymChoices.addGym(named: "Home", in: context)
        let older = GymChoices.addMachine(named: "Chest Press A", at: downtown, in: context)
        let newer = GymChoices.addMachine(named: "Chest Press B", at: downtown, in: context)
        let elsewhere = GymChoices.addMachine(named: "Chest Press Home", at: home, in: context)
        logged(at: downtown, on: 1, machine: older)
        logged(at: downtown, on: 2, machine: newer)
        logged(at: home, on: 3, machine: elsewhere)
        logged(at: downtown, on: 4, machine: nil)
        try context.save()

        let history = ExerciseHistory.fetch(in: context)
        let identity = ExerciseIdentity(name: "Chest Press", catalogKey: nil)
        #expect(GymChoices.suggestedMachine(for: identity, at: downtown, in: history)?.id == newer.id)
        #expect(GymChoices.suggestedMachine(for: identity, at: nil, in: history) == nil)
        let fresh = GymChoices.addGym(named: "Fresh", in: context)
        #expect(GymChoices.suggestedMachine(for: identity, at: fresh, in: history) == nil)
    }

    /// Picked in a workout at a gym it was not in, a machine stands there
    /// from then on.
    @Test func aMachinePickedFromElsewhereStandsInTheGymFromThenOn() {
        let gym = GymChoices.addGym(named: "Downtown Gym", in: context)
        let machine = GymChoices.addMachine(named: "Chest Press", at: nil, in: context)
        let workout = WorkoutSession(name: "Push")
        context.insert(workout)
        workout.gym = gym
        let entry = ExerciseEntry(name: "Chest Press", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        context.insert(entry)

        GymChoices.pick(machine, for: entry)
        #expect(entry.machine?.id == machine.id)
        #expect(gym.machines.map(\.id) == [machine.id])

        GymChoices.pick(nil, for: entry)
        #expect(entry.machine == nil)
        #expect(gym.machines.map(\.id) == [machine.id])
    }

    private func logged(at gym: Gym, on day: Int, machine: Machine?) {
        let workout = WorkoutSession(name: "Push", date: Date(timeIntervalSinceReferenceDate: Double(day) * 86_400))
        context.insert(workout)
        workout.gym = gym
        let entry = ExerciseEntry(name: "Chest Press", notes: "logged", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        context.insert(entry)
        entry.machine = machine
    }
}
