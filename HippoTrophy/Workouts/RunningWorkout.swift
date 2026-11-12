import Foundation
import Observation

/// The workout being trained: what the editor needs to go on with it after
/// it was left — for the start screen, or by a quit app. The workout itself
/// is in the store from its start on; this is what is not in the workout.
struct RunningWorkout: Codable, Equatable {
    let sessionID: UUID
    /// When the training began, for the clock. Nil once the workout's date
    /// was moved by hand: it is being logged afterwards, not timed.
    var startedAt: Date?
    // Builds up to 24 also kept whether Finish asked to keep a template.
    // Finish no longer asks; a workout carried over from such a build
    // decodes as it is, the flag left unread.
    /// The day variant the workout was started from, which Finish uses up.
    let usesUpID: UUID?
    /// What this workout changed about the editor. Optional so a workout
    /// carried over from a build without it still decodes.
    var editorOverrides: EditorSettingsOverrides?
}

/// The one workout being trained, for the whole app: one at a time, kept
/// across launches. Leaving the editor goes on with it; only Finish and
/// Discard end it.
@MainActor
@Observable
final class RunningWorkoutCenter {
    static let shared = RunningWorkoutCenter(defaults: .standard)

    /// The workout running, nil when none is.
    private(set) var running: RunningWorkout? {
        didSet { persist() }
    }

    /// What the workout looked like at its start, so Discard can tell
    /// whether anything would be lost. Not kept across launches: after one,
    /// Discard always asks.
    @ObservationIgnored private(set) var initialSnapshot: WorkoutSnapshot?

    @ObservationIgnored private let defaults: UserDefaults
    /// Not a `SettingsKey`: this is state, not a setting, and a backup has
    /// no business carrying it.
    static let defaultsKey = "runningWorkout"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        running = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(RunningWorkout.self, from: $0) }
    }

    /// Whether `sessionID` is the workout being trained.
    func isRunning(_ sessionID: UUID) -> Bool {
        running?.sessionID == sessionID
    }

    func start(_ sessionID: UUID, at date: Date, usesUpID: UUID?, initialSnapshot: WorkoutSnapshot?) {
        running = RunningWorkout(sessionID: sessionID, startedAt: date, usesUpID: usesUpID)
        self.initialSnapshot = initialSnapshot
    }

    /// The editor's settings were changed for this workout.
    func setEditorOverrides(_ overrides: EditorSettingsOverrides) {
        running?.editorOverrides = overrides.isEmpty ? nil : overrides
    }

    /// The workout's date was set by hand: it is logged, no longer timed.
    func stopClock() {
        running?.startedAt = nil
    }

    /// Finished or discarded.
    func end() {
        running = nil
        initialSnapshot = nil
    }

    /// Forgets a workout that is no longer there — deleted, or gone with a
    /// restored backup. `exists` says whether a workout with an id is.
    func forgetIfGone(exists: (UUID) -> Bool) {
        guard let running, !exists(running.sessionID) else { return }
        end()
    }

    private func persist() {
        if let running, let data = try? JSONEncoder().encode(running) {
            defaults.set(data, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }
}
