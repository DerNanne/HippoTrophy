import ActivityKit
import Foundation

/// The rest on the lock screen and in the Dynamic Island. Shared by the app,
/// which starts and moves it, and the widget extension, which draws it; the
/// two must agree on this shape, so it lives once, in `Shared/`.
///
/// Everything lives in the state: a rest changes its end with every tap on
/// minus or plus, and the next one may follow another exercise.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var exerciseName: String
        /// When the rest began, adjustments included — the start of the bar.
        var startedAt: Date
        var endsAt: Date
        /// What was left when the rest was paused; nil while it runs.
        var pausedRemaining: TimeInterval?
        /// The whole rest, which a paused rest no longer reads from its span.
        var totalSeconds: Int
        /// A rest between the two sides of a set, not after one.
        var isBetweenSides: Bool

        /// The span the countdown and the bar run over. Never empty: a range
        /// whose ends meet draws nothing.
        var interval: ClosedRange<Date> {
            startedAt...max(endsAt, startedAt.addingTimeInterval(1))
        }
    }
}
