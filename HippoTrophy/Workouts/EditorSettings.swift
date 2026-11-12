import Foundation

/// What the workout editor goes by, resolved: the section of the same name in
/// Settings, with whatever this workout changed for itself on top.
nonisolated struct EditorSettings: Equatable {
    var collapseOtherExercises: Bool
    var showLastPerformance: Bool
    var showExerciseTexts: Bool
    var startWithOneSet: Bool
    var guideThroughWorkout: Bool
    var defaultRestSeconds: Int
    var betweenSidesRestSeconds: Int
    /// How exercises added from here on rate their sets.
    var effortScale: EffortScale
    var sideLayout: SideLayout
}

/// What one workout changed about the editor. Nil follows Settings, so a
/// setting left alone here still moves with its default there. Lives as long
/// as the workout is being edited, and never reaches the defaults: a workout
/// changes itself, not the next one.
nonisolated struct EditorSettingsOverrides: Codable, Equatable {
    var collapseOtherExercises: Bool?
    var showLastPerformance: Bool?
    var showExerciseTexts: Bool?
    var startWithOneSet: Bool?
    var guideThroughWorkout: Bool?
    var defaultRestSeconds: Int?
    var betweenSidesRestSeconds: Int?
    var effortScale: EffortScale?
    var sideLayout: SideLayout?

    var isEmpty: Bool {
        self == EditorSettingsOverrides()
    }

    func applied(to defaults: EditorSettings) -> EditorSettings {
        EditorSettings(
            collapseOtherExercises: collapseOtherExercises ?? defaults.collapseOtherExercises,
            showLastPerformance: showLastPerformance ?? defaults.showLastPerformance,
            showExerciseTexts: showExerciseTexts ?? defaults.showExerciseTexts,
            startWithOneSet: startWithOneSet ?? defaults.startWithOneSet,
            guideThroughWorkout: guideThroughWorkout ?? defaults.guideThroughWorkout,
            defaultRestSeconds: defaultRestSeconds ?? defaults.defaultRestSeconds,
            betweenSidesRestSeconds: betweenSidesRestSeconds ?? defaults.betweenSidesRestSeconds,
            effortScale: effortScale ?? defaults.effortScale,
            sideLayout: sideLayout ?? defaults.sideLayout
        )
    }

    /// Changes one setting. Back at its default it follows the default again,
    /// rather than holding on to the value it happens to have today.
    mutating func set<Value: Equatable>(
        _ override: WritableKeyPath<EditorSettingsOverrides, Value?>,
        to value: Value,
        default defaultValue: Value
    ) {
        self[keyPath: override] = value == defaultValue ? nil : value
    }
}
