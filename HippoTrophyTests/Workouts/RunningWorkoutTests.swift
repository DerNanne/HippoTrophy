import Foundation
import Testing
@testable import HippoTrophy

@MainActor
struct RunningWorkoutTests {
    private let defaults: UserDefaults

    init() {
        let suite = "RunningWorkoutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func start(_ center: RunningWorkoutCenter, _ id: UUID = UUID(), usesUpID: UUID? = nil) -> UUID {
        center.start(id, at: Date(timeIntervalSinceReferenceDate: 1000), usesUpID: usesUpID, initialSnapshot: nil)
        return id
    }

    @Test func nothingRunsAtFirst() {
        #expect(RunningWorkoutCenter(defaults: defaults).running == nil)
    }

    /// A quit app comes back to the workout, with its clock where it was.
    @Test func aWorkoutRunsOnAfterALaunch() {
        let variant = UUID()
        let id = start(RunningWorkoutCenter(defaults: defaults), usesUpID: variant)

        let relaunched = RunningWorkoutCenter(defaults: defaults)
        #expect(relaunched.running == RunningWorkout(
            sessionID: id,
            startedAt: Date(timeIntervalSinceReferenceDate: 1000),
            usesUpID: variant
        ))
        #expect(relaunched.isRunning(id))
        #expect(!relaunched.isRunning(UUID()))
    }

    /// A workout left running in a build that still asked about a template
    /// at Finish carries the flag along; this build reads it as it is.
    @Test func aWorkoutFromABuildThatAskedAboutATemplateRunsOn() throws {
        let id = UUID()
        let stored = #"{"sessionID":"\#(id.uuidString)","startedAt":1000,"asksToKeepTemplate":true}"#
        defaults.set(Data(stored.utf8), forKey: RunningWorkoutCenter.defaultsKey)

        let relaunched = RunningWorkoutCenter(defaults: defaults)
        #expect(relaunched.running == RunningWorkout(sessionID: id, startedAt: Date(timeIntervalSinceReferenceDate: 1000), usesUpID: nil))
    }

    @Test func finishedItIsGoneForTheNextLaunchToo() {
        let center = RunningWorkoutCenter(defaults: defaults)
        _ = start(center)
        center.end()

        #expect(center.running == nil)
        #expect(RunningWorkoutCenter(defaults: defaults).running == nil)
    }

    /// A date set by hand means the workout is logged afterwards; the clock
    /// stays stopped after a launch too.
    @Test func aStoppedClockStaysStopped() {
        let center = RunningWorkoutCenter(defaults: defaults)
        let id = start(center)
        center.stopClock()

        let relaunched = RunningWorkoutCenter(defaults: defaults)
        #expect(relaunched.isRunning(id))
        #expect(relaunched.running?.startedAt == nil)
    }

    @Test func aWorkoutNoLongerThereIsForgotten() {
        let center = RunningWorkoutCenter(defaults: defaults)
        let id = start(center)

        center.forgetIfGone { $0 == id }
        #expect(center.isRunning(id))

        center.forgetIfGone { _ in false }
        #expect(center.running == nil)
        #expect(RunningWorkoutCenter(defaults: defaults).running == nil)
    }

    /// The start is only known to the launch that saw it: after another,
    /// Discard has nothing to compare with and asks.
    @Test func theStartIsNotKeptAcrossLaunches() throws {
        let center = RunningWorkoutCenter(defaults: defaults)
        center.start(UUID(), at: .now, usesUpID: nil, initialSnapshot: WorkoutSnapshot(session: WorkoutSession()))
        #expect(center.initialSnapshot != nil)
        #expect(RunningWorkoutCenter(defaults: defaults).initialSnapshot == nil)
    }

    @Test func somethingUnreadableIsNothingRunning() {
        defaults.set(Data("not json".utf8), forKey: RunningWorkoutCenter.defaultsKey)
        #expect(RunningWorkoutCenter(defaults: defaults).running == nil)
    }
}
