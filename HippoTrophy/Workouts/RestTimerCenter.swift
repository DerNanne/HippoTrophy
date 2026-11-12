import ActivityKit
import Foundation
import Observation
import UserNotifications

/// The one rest running, and everything outside the app that has to know
/// about it: the notification at its end, for a phone put away, and the Live
/// Activity on the lock screen and in the Dynamic Island. `RestTimer` does
/// the arithmetic; this carries it out.
///
/// There is one, for the whole app: a rest belongs to the workout being
/// trained, and the editor that shows it may be closed and opened again.
@MainActor
@Observable
final class RestTimerCenter: NSObject {
    static let shared = RestTimerCenter()

    /// The rest running, nil when there is none.
    private(set) var timer: RestTimer?
    /// Counts the rests that ran to their end with the app open, so a view
    /// can buzz on each.
    private(set) var finishedCount = 0
    /// The set whose rest ended last, nil for one started by hand — where
    /// the editor's guide goes on from.
    private(set) var lastFinishedSetID: UUID?

    @ObservationIgnored private var activity: Activity<RestActivityAttributes>?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    private static let notificationID = "rest-timer"

    private override init() {
        super.init()
        // In the foreground the bar is on screen, so the end only sounds.
        UNUserNotificationCenter.current().delegate = self
    }

    func start(seconds: Int, exerciseName: String, setID: UUID? = nil, kind: RestKind = .afterSet) {
        let timer = RestTimer(seconds: seconds, exerciseName: exerciseName, setID: setID, kind: kind, from: .now)
        self.timer = timer
        askForNotificationsOnce()
        scheduleNotification(for: timer)
        showActivity(for: timer)
        waitForTheEnd(of: timer)
    }

    /// Minus or plus: the end moves by `seconds`, everywhere at once.
    func adjust(by seconds: TimeInterval) {
        guard var timer else { return }
        timer.adjust(by: seconds, at: .now)
        guard !timer.isOver(at: .now) else {
            stop()
            return
        }
        apply(timer)
    }

    /// Stops the countdown where it is: no notification while it stands,
    /// and the lock screen shows what is left without counting.
    func pause() {
        guard var timer, !timer.isPaused else { return }
        timer.pause(at: .now)
        apply(timer)
    }

    func resume() {
        guard var timer, timer.isPaused else { return }
        timer.resume(at: .now)
        apply(timer)
    }

    /// Hands a changed rest to everything that shows or ends it. A paused
    /// one has no end to wait for or to announce.
    private func apply(_ timer: RestTimer) {
        self.timer = timer
        showActivity(for: timer)
        if timer.isPaused {
            endTask?.cancel()
            endTask = nil
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        } else {
            scheduleNotification(for: timer)
            waitForTheEnd(of: timer)
        }
    }

    /// Skip, or the workout closed: no rest, no notification, nothing on
    /// the lock screen.
    func stop() {
        timer = nil
        endTask?.cancel()
        endTask = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        endActivity()
    }

    /// Back in the foreground: a rest that ended while the app slept is
    /// over, as if it had ended in front of the user, and its Live Activity,
    /// stale since, goes.
    func refresh() {
        if let timer, timer.isOver(at: .now) {
            finish(timer)
        } else if timer == nil {
            endActivity()
        }
    }

    // MARK: - The end, in the app

    private func waitForTheEnd(of timer: RestTimer) {
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timer.remaining(at: .now)))
            guard !Task.isCancelled, let self else { return }
            self.finish(timer)
        }
    }

    private func finish(_ timer: RestTimer) {
        guard self.timer == timer else { return }
        endTask?.cancel()
        endTask = nil
        lastFinishedSetID = timer.setID
        finishedCount += 1
        self.timer = nil
        // The notification fires on its own and only sounds here, so it
        // stays; the Live Activity has nothing left to count.
        endActivity()
    }

    // MARK: - Notification

    private func askForNotificationsOnce() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    private func scheduleNotification(for timer: RestTimer) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        let content = UNMutableNotificationContent()
        switch timer.kind {
        case .afterSet:
            content.title = "Rest Over"
            content.body = timer.exerciseName.isEmpty
                ? "Time for the next set."
                : "Time for the next set of \(timer.exerciseName)."
        case .betweenSides:
            content.title = "Switch Sides"
            content.body = "Time for the other side of \(timer.exerciseName)."
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.remaining(at: .now)), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }

    // MARK: - Live Activity

    private func showActivity(for timer: RestTimer) {
        let state = RestActivityAttributes.ContentState(
            exerciseName: timer.exerciseName,
            startedAt: timer.endsAt.addingTimeInterval(-timer.duration),
            endsAt: timer.endsAt,
            pausedRemaining: timer.pausedRemaining,
            totalSeconds: timer.totalSeconds,
            isBetweenSides: timer.kind == .betweenSides
        )
        // Stale from its end on: the lock screen then says the rest is over
        // without the app having to wake up for it. A paused rest has no end.
        let content = ActivityContent(state: state, staleDate: timer.isPaused ? nil : timer.endsAt)
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes: RestActivityAttributes(), content: content)
    }

    private func endActivity() {
        let ending = activity
        activity = nil
        Task {
            await ending?.end(nil, dismissalPolicy: .immediate)
            // One left behind by a run of the app that did not get to end it
            // — but not a rest started since this was asked for.
            for leftover in Activity<RestActivityAttributes>.activities where leftover.id != activity?.id {
                await leftover.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

extension RestTimerCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.sound]
    }
}
