import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// Help from a machine in place of the weight: what a set logs, what it adds
/// up to, and how an entry's sets follow the switch.
@MainActor
struct AssistanceTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func pullUp(in context: ModelContext, offersAssistance: Bool = true) -> ExerciseDefinition {
        let definition = ExerciseDefinition.insertPlainSetsAndReps(name: "Pull-Up", orderIndex: 0, in: context)
        definition.offersAssistance = offersAssistance
        return definition
    }

    private func entry(of definition: ExerciseDefinition, assistance: Assistance, in context: ModelContext) -> ExerciseEntry {
        let session = WorkoutSession()
        context.insert(session)
        let entry = ExerciseEntry(name: definition.name, orderIndex: 0, definitionID: definition.id, effortScale: .off, assistance: assistance, session: session)
        context.insert(entry)
        return entry
    }

    private func weightValue(_ set: SetEntry) throws -> FieldValue {
        try #require(set.values.first { $0.fieldKey == "weight" })
    }

    // MARK: What a set logs

    @Test func onlyTheWeightIsLoggedAsHelp() {
        #expect(Assistance.machine.loggedType(for: .weight) == .assistance)
        #expect(Assistance.machine.loggedType(for: .reps) == .reps)
        #expect(Assistance.unassisted.loggedType(for: .weight) == .weight)
        #expect(Assistance.machine.loggedLabel(for: .weight, label: "Weight") == "Assist")
        #expect(Assistance.machine.loggedLabel(for: .reps, label: "Reps") == "Reps")
    }

    @Test func aSetOfAnAssistedEntryLogsTheHelpUnderTheWeightsKey() throws {
        let context = try context()
        let entry = entry(of: pullUp(in: context), assistance: .machine, in: context)

        let set = entry.addSet(on: .both, definition: pullUp(in: context), in: context)

        #expect(set.sortedValues.map(\.fieldKey) == ["weight", "reps"])
        #expect(set.sortedValues.map(\.type) == [.assistance, .reps])
        #expect(set.sortedValues.map(\.label) == ["Assist", "Reps"])
    }

    @Test func helpIsTypedLikeAWeightAndStoredInKilograms() throws {
        let context = try context()
        let entry = entry(of: pullUp(in: context), assistance: .machine, in: context)
        let set = entry.addSet(on: .both, definition: pullUp(in: context), in: context)
        let help = try weightValue(set)

        help.applyInput("22,5", unit: .kilograms)
        #expect(help.numberValue == 22.5)
        #expect(help.displayText(unit: .kilograms) == WeightUnit.kilograms.formatted(kilograms: 22.5))
        help.applyInput("50", unit: .pounds)
        #expect(abs((help.numberValue ?? 0) - WeightUnit.pounds.kilograms(from: 50)) < 1e-9)
    }

    /// The whole point of a type of its own: what adds up weight never sees it.
    @Test func anAssistedSetIsWeightTrainingWithoutAWeight() throws {
        let context = try context()
        let entry = entry(of: pullUp(in: context), assistance: .machine, in: context)
        let set = entry.addSet(on: .both, definition: pullUp(in: context), in: context)
        try weightValue(set).numberValue = 25
        set.values.first { $0.fieldKey == "reps" }?.numberValue = 8

        #expect(set.logsWeightAndReps)
        #expect(set.weightKg == nil)
        #expect(set.assistanceKg == 25)
    }

    // MARK: Switching

    @Test func switchingMovesTheNumberOverAndBack() throws {
        let context = try context()
        let definition = pullUp(in: context)
        let entry = entry(of: definition, assistance: .unassisted, in: context)
        let set = entry.addSet(on: .both, definition: definition, in: context)
        try weightValue(set).numberValue = 30

        entry.applyAssistance(.machine)
        #expect(entry.assistance == .machine)
        #expect(try weightValue(set).type == .assistance)
        #expect(try weightValue(set).label == "Assist")
        #expect(try weightValue(set).numberValue == 30)

        entry.applyAssistance(.unassisted)
        #expect(try weightValue(set).type == .weight)
        #expect(try weightValue(set).label == "Weight")
        #expect(try weightValue(set).numberValue == 30)
    }

    /// The editor lines every set up with its definition after a field
    /// change, and an import does the same — neither may turn the help back
    /// into a weight.
    @Test func liningASetUpWithItsDefinitionKeepsTheHelp() throws {
        let context = try context()
        let definition = pullUp(in: context)
        let entry = entry(of: definition, assistance: .machine, in: context)
        let set = entry.addSet(on: .both, definition: definition, in: context)
        try weightValue(set).numberValue = 25

        ExerciseMerging.align(set, to: definition, keyRewrite: [:], in: context)

        #expect(try weightValue(set).type == .assistance)
        #expect(try weightValue(set).label == "Assist")
        #expect(try weightValue(set).numberValue == 25)
    }

    // MARK: Starting and choosing

    @Test func aNewEntryStartsWithTheHelpOfLastTimeIfTheExerciseStillOffersIt() {
        #expect(Assistance.start(offered: true, lastLogged: .machine) == .machine)
        #expect(Assistance.start(offered: true, lastLogged: nil) == .unassisted)
        #expect(Assistance.start(offered: false, lastLogged: .machine) == .unassisted)
    }

    @Test func anAssistedEntryKeepsItsWayBackWhenTheExerciseNoLongerOffersHelp() {
        #expect(Assistance.choices(offered: true, current: .unassisted) == Assistance.allCases)
        #expect(Assistance.choices(offered: false, current: .unassisted).isEmpty)
        #expect(Assistance.choices(offered: false, current: .machine) == Assistance.allCases)
    }

    @Test func aCopiedWorkoutKeepsTheHelp() throws {
        let context = try context()
        let definition = pullUp(in: context)
        let entry = entry(of: definition, assistance: .machine, in: context)
        let set = entry.addSet(on: .both, definition: definition, in: context)
        try weightValue(set).numberValue = 25
        let session = try #require(entry.session)

        let copy = session.copy(dated: .now)

        let copied = try #require(copy.exercises.first)
        #expect(copied.assistance == .machine)
        #expect(copied.sets.first?.assistanceKg == 25)
    }
}
