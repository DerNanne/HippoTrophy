import Foundation
import Testing
@testable import HippoTrophy

struct EditorSettingsTests {
    private let defaults = EditorSettings(
        collapseOtherExercises: false,
        showLastPerformance: true,
        showExerciseTexts: true,
        startWithOneSet: false,
        guideThroughWorkout: true,
        defaultRestSeconds: 120,
        betweenSidesRestSeconds: 30,
        effortScale: .levels,
        sideLayout: .tabs
    )

    @Test func withoutChangesTheDefaultsHold() {
        #expect(EditorSettingsOverrides().applied(to: defaults) == defaults)
        #expect(EditorSettingsOverrides().isEmpty)
    }

    @Test func aChangeHoldsForItsSettingAlone() {
        var overrides = EditorSettingsOverrides()
        overrides.set(\.defaultRestSeconds, to: 60, default: defaults.defaultRestSeconds)

        var expected = defaults
        expected.defaultRestSeconds = 60
        #expect(overrides.applied(to: defaults) == expected)
        #expect(!overrides.isEmpty)
    }

    /// Everything can be changed: a new setting forgotten in `applied(to:)`
    /// would silently keep its default.
    @Test func everySettingCanBeChanged() {
        let changed = EditorSettings(
            collapseOtherExercises: true,
            showLastPerformance: false,
            showExerciseTexts: false,
            startWithOneSet: true,
            guideThroughWorkout: false,
            defaultRestSeconds: 60,
            betweenSidesRestSeconds: 0,
            effortScale: .rir,
            sideLayout: .list
        )
        let overrides = EditorSettingsOverrides(
            collapseOtherExercises: true,
            showLastPerformance: false,
            showExerciseTexts: false,
            startWithOneSet: true,
            guideThroughWorkout: false,
            defaultRestSeconds: 60,
            betweenSidesRestSeconds: 0,
            effortScale: .rir,
            sideLayout: .list
        )
        #expect(overrides.applied(to: defaults) == changed)
    }

    /// Set back by hand it follows Settings again, and no longer counts as
    /// changed.
    @Test func backAtItsDefaultASettingFollowsTheDefault() {
        var overrides = EditorSettingsOverrides()
        overrides.set(\.guideThroughWorkout, to: false, default: true)
        overrides.set(\.guideThroughWorkout, to: true, default: true)
        #expect(overrides.isEmpty)

        var later = defaults
        later.guideThroughWorkout = false
        #expect(overrides.applied(to: later).guideThroughWorkout == false)
    }

    /// A workout carried over from a build without these has none, and must
    /// still decode: losing it would lose the running workout.
    @Test func aRunningWorkoutFromBeforeTheseStillDecodes() throws {
        let id = UUID()
        let json = #"{"sessionID":"\#(id.uuidString)"}"#
        let running = try JSONDecoder().decode(RunningWorkout.self, from: Data(json.utf8))
        #expect(running.sessionID == id)
        #expect(running.editorOverrides == nil)
    }

    @MainActor
    @Test func aRunningWorkoutKeepsItsChangesAcrossALaunchAndNotBeyondItsEnd() {
        let suite = "EditorSettingsTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let center = RunningWorkoutCenter(defaults: store)
        center.start(UUID(), at: .now, usesUpID: nil, initialSnapshot: nil)
        center.setEditorOverrides(EditorSettingsOverrides(defaultRestSeconds: 60))

        let relaunched = RunningWorkoutCenter(defaults: store)
        #expect(relaunched.running?.editorOverrides?.defaultRestSeconds == 60)

        relaunched.end()
        relaunched.start(UUID(), at: .now, usesUpID: nil, initialSnapshot: nil)
        #expect(relaunched.running?.editorOverrides == nil)
    }
}
