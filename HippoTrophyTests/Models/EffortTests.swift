import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// A set's rating is a bare number that only its entry's scale can read. What
/// matters: a set nobody rated never reads as a rating, and a number the
/// scale has no meaning for is not guessed into one.
@MainActor
struct EffortTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func everyLevelSurvivesTheStoredValue() {
        for effort in EffortScale.levels.choices {
            #expect(EffortScale.levels.effort(storedAs: effort.storedValue) == effort)
            #expect(effort.scale == .levels)
        }
    }

    @Test func nothingStoredIsNotRatedOnAnyScale() {
        for scale in EffortScale.allCases {
            #expect(scale.effort(storedAs: nil) == nil)
        }
    }

    /// An entry that rates nothing shows nothing, whatever a set still holds.
    @Test func offReadsNoRatingEvenWhenOneIsStored() {
        #expect(EffortScale.off.effort(storedAs: SetEffort.level(.hard).storedValue) == nil)
        #expect(EffortScale.off.choices.isEmpty)
    }

    @Test func aValueTheScaleCannotHoldReadsAsNotRated() {
        for value in [-1, 1.5, 3, 10] {
            #expect(EffortScale.levels.effort(storedAs: value) == nil)
        }
    }

    @Test func anUnsetSettingStartsNewEntriesOnLevels() {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: SettingsKey.effortScale)
        defer { defaults.set(before, forKey: SettingsKey.effortScale) }

        defaults.removeObject(forKey: SettingsKey.effortScale)
        #expect(EffortScale.forNewEntries == .levels)

        defaults.set(EffortScale.off.rawValue, forKey: SettingsKey.effortScale)
        #expect(EffortScale.forNewEntries == .off)
    }

    @Test func levelsAreOfferedFromEasyToHard() {
        #expect(EffortScale.levels.choices == [.level(.easy), .level(.normal), .level(.hard)])
    }

    /// The point of dropping the old default: a set added and never touched
    /// is not rated, rather than quietly "normal".
    @Test func aNewSetIsNotRated() throws {
        let context = try context()
        let entry = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .levels)
        context.insert(entry)
        let set = entry.addSet(on: .both, definition: nil, in: context)

        #expect(set.effortValue == nil)
        #expect(set.effort == nil)
    }

    @Test func aRatingIsReadThroughTheEntrysScale() throws {
        let context = try context()
        let entry = ExerciseEntry(name: "Bench", orderIndex: 0, definitionID: UUID(), effortScale: .levels)
        context.insert(entry)
        let set = entry.addSet(on: .both, definition: nil, in: context)

        set.effort = .level(.hard)
        #expect(set.effort == .level(.hard))
        set.effort = nil
        #expect(set.effortValue == nil)
    }

    @Test func aSetWithoutAnEntryHasNoRating() {
        let set = SetEntry(setNumber: 1, effortValue: SetEffort.level(.easy).storedValue)
        #expect(set.effort == nil)
    }

    @Test func everyHalfStepOfRepsInReserveSurvivesTheStoredValue() {
        for steps in 0...20 {
            let rir = Double(steps) / 2
            #expect(EffortScale.rir.effort(storedAs: rir) == .rir(rir))
        }
    }

    @Test func repsInReserveOutsideTheRangeOrBetweenHalvesIsNotRated() {
        for value in [-0.5, 10.5, 1.25, 2.1] {
            #expect(EffortScale.rir.effort(storedAs: value) == nil)
        }
    }

    /// The scales do not translate: a stored "hard" is not some reps in
    /// reserve, and 4 reps in reserve are nothing on the three-step scale.
    @Test func aValueReadsOnlyOnItsOwnScale() {
        #expect(EffortScale.rir.effort(storedAs: SetEffort.level(.hard).storedValue) == .rir(2))
        #expect(EffortScale.levels.effort(storedAs: 4) == nil)
    }

    @Test func repsInReserveAreOfferedOnePresetPerBandHardestFirst() {
        #expect(EffortScale.rir.choices == [0, 0.5, 1, 2, 3, 4].map(SetEffort.rir))
        #expect(RIRBand.allCases.map(\.presetLabel).last == "4+")
    }

    @Test func eachPresetLiesInItsOwnBand() {
        for band in RIRBand.allCases {
            #expect(RIRBand.containing(band.preset) == band)
        }
    }

    /// A value stepped to between presets takes the band it falls in, so it
    /// is never left without a colour.
    @Test func aValueBetweenPresetsTakesTheBandBelow() {
        #expect(RIRBand.containing(1.5) == .oneRep)
        #expect(RIRBand.containing(2.5) == .twoReps)
        #expect(RIRBand.containing(3.5) == .threeReps)
        #expect(RIRBand.containing(7) == .fourOrMore)
        #expect(RIRBand.containing(10) == .fourOrMore)
    }
}

