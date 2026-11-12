import Foundation
import Testing
@testable import HippoTrophy

struct RestTimerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func countsDownToItsEnd() {
        let timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        #expect(timer.remaining(at: start) == 120)
        #expect(timer.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(timer.fractionLeft(at: start.addingTimeInterval(30)) == 0.75)
        #expect(!timer.isOver(at: start.addingTimeInterval(119)))
        #expect(timer.isOver(at: start.addingTimeInterval(120)))
    }

    @Test func aRestIsAfterASetUnlessSaidOtherwise() {
        #expect(RestTimer(seconds: 60, exerciseName: "Row", from: start).kind == .afterSet)
    }

    /// Minus, plus and a pause leave it what it is: the bar stays purple.
    @Test func aRestBetweenSidesStaysOneWhileAdjusted() {
        var timer = RestTimer(seconds: 30, exerciseName: "Row", kind: .betweenSides, from: start)
        timer.pause(at: start.addingTimeInterval(5))
        timer.adjust(by: RestTimer.step, at: start.addingTimeInterval(5))
        timer.resume(at: start.addingTimeInterval(10))
        #expect(timer.kind == .betweenSides)
    }

    /// A phone put away for longer than the rest comes back to zero, not to
    /// a negative number.
    @Test func neverGoesBelowZero() {
        let timer = RestTimer(seconds: 60, exerciseName: "Bench", from: start)
        let later = start.addingTimeInterval(500)
        #expect(timer.remaining(at: later) == 0)
        #expect(timer.fractionLeft(at: later) == 0)
    }

    /// Paused, the rest keeps what was left however long the pause; resumed,
    /// it runs on from there.
    @Test func aPausedRestKeepsWhatWasLeft() {
        var timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        timer.pause(at: start.addingTimeInterval(30))
        #expect(timer.isPaused)
        #expect(timer.remaining(at: start.addingTimeInterval(500)) == 90)
        #expect(!timer.isOver(at: start.addingTimeInterval(500)))
        #expect(timer.fractionLeft(at: start.addingTimeInterval(500)) == 0.75)

        timer.resume(at: start.addingTimeInterval(500))
        #expect(!timer.isPaused)
        #expect(timer.remaining(at: start.addingTimeInterval(530)) == 60)
        #expect(timer.isOver(at: start.addingTimeInterval(590)))
    }

    @Test func plusAndMinusWorkWhilePaused() {
        var timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        timer.pause(at: start.addingTimeInterval(100))
        timer.adjust(by: RestTimer.step, at: start.addingTimeInterval(200))
        #expect(timer.remaining(at: start.addingTimeInterval(300)) == 35)
        #expect(timer.totalSeconds == 135)
        timer.adjust(by: -60, at: start.addingTimeInterval(300))
        #expect(timer.isOver(at: start.addingTimeInterval(300)))
    }

    /// A second pause does not reset what was left to the moment of the
    /// second tap.
    @Test func pausingTwiceChangesNothing() {
        var timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        timer.pause(at: start.addingTimeInterval(30))
        timer.pause(at: start.addingTimeInterval(60))
        #expect(timer.remaining(at: start.addingTimeInterval(60)) == 90)
    }

    /// "1:45 / 2:00": plus and minus move the whole rest with what is left.
    @Test func theWholeRestFollowsPlusAndMinus() {
        var timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        #expect(timer.totalSeconds == 120)
        timer.adjust(by: RestTimer.step, at: start.addingTimeInterval(10))
        #expect(timer.totalSeconds == 135)
        timer.adjust(by: -RestTimer.step, at: start.addingTimeInterval(20))
        timer.adjust(by: -RestTimer.step, at: start.addingTimeInterval(20))
        #expect(timer.totalSeconds == 105)
    }

    @Test func plusAndMinusMoveTheEndAndTheWhole() {
        var timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        let now = start.addingTimeInterval(60)
        timer.adjust(by: RestTimer.step, at: now)
        #expect(timer.remaining(at: now) == 75)
        #expect(timer.duration == 135)
        timer.adjust(by: -RestTimer.step * 2, at: now)
        #expect(timer.remaining(at: now) == 45)
        #expect(timer.duration == 105)
    }

    /// Minus with less than a step left ends the rest now; the end does not
    /// move into the past.
    @Test func minusPastTheEndEndsItNow() {
        var timer = RestTimer(seconds: 120, exerciseName: "Bench", from: start)
        let now = start.addingTimeInterval(110)
        timer.adjust(by: -RestTimer.step, at: now)
        #expect(timer.isOver(at: now))
        #expect(timer.endsAt == now)
        #expect(timer.duration == 110)
    }

    @Test func anExercisesOwnRestWinsOverTheSetting() {
        #expect(RestDuration.seconds(exercise: 90, setting: 120) == 90)
        #expect(RestDuration.seconds(exercise: nil, setting: 120) == 120)
    }

    @Test func zeroIsNoTimerWhereverItComesFrom() {
        #expect(RestDuration.seconds(exercise: 0, setting: 120) == nil)
        #expect(RestDuration.seconds(exercise: nil, setting: 0) == nil)
        #expect(RestDuration.seconds(exercise: 90, setting: 0) == 90)
    }

    @Test func readsAsMinutesOrOff() {
        #expect(RestDuration.text(120) == "2:00")
        #expect(RestDuration.text(75) == "1:15")
        #expect(RestDuration.text(0) == "Off")
    }

    @Test func everySetOutsideASupersetRests() {
        #expect(RestAfterSet.rests(afterSetAt: 0, in: Optional<[String]>.none))
    }

    /// A1 B1 A2 B2: the leading exercise hands over to the other without a
    /// rest; the round rests after the second.
    @Test func aSupersetRestsAfterEachRound() {
        let members = ["A", "B", "A", "B"]
        #expect(members.indices.map { RestAfterSet.rests(afterSetAt: $0, in: members) } == [false, true, false, true])
    }

    /// A1 A2 B1 B2, sets moved into blocks: a set followed by its own
    /// exercise rests as any set does.
    @Test func aSupersetInBlocksRestsBetweenSetsOfOneExercise() {
        let members = ["A", "A", "B", "B"]
        #expect(members.indices.map { RestAfterSet.rests(afterSetAt: $0, in: members) } == [true, false, true, true])
    }
}
