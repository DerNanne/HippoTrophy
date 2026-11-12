import Foundation
import Testing
@testable import HippoTrophy

@MainActor
struct SetTickTests {
    @Test func sameWeightTakesATapPerSide() {
        var tick = SetTick.open
        tick = tick.tapped(mode: .oneSided)
        #expect(tick == .oneSideDone)
        tick = tick.tapped(mode: .oneSided)
        #expect(tick == .done)
    }

    @Test func aTickComesOutInOneTap() {
        #expect(SetTick.done.tapped(mode: .oneSided) == .open)
        #expect(SetTick.done.tapped(mode: .bilateral) == .open)
    }

    @Test func theOtherModesTakeOneTap() {
        #expect(SetTick.open.tapped(mode: .bilateral) == .done)
        #expect(SetTick.open.tapped(mode: .perSide) == .done)
    }

    /// Next on the keyboard and Mark Done set `isDone` directly; a side
    /// ticked before that has nothing left to say.
    @Test func doneOutranksOneSide() {
        #expect(SetTick(isDone: true, oneSideDone: true, mode: .oneSided) == .done)
    }

    @Test func oneSideIsReadOnlyInSameWeight() {
        #expect(SetTick(isDone: false, oneSideDone: true, mode: .oneSided) == .oneSideDone)
        #expect(SetTick(isDone: false, oneSideDone: true, mode: .perSide) == .open)
        #expect(SetTick(isDone: false, oneSideDone: true, mode: .bilateral) == .open)
        #expect(SetTick(isDone: false, oneSideDone: false, mode: .oneSided) == .open)
    }

    @Test func oneSideTicksRememberEachSet() {
        let ticks = OneSideTicks()
        let first = UUID()
        let second = UUID()
        ticks.set(first, oneSideDone: true)
        ticks.set(second, oneSideDone: true)
        ticks.set(first, oneSideDone: false)
        #expect(!ticks.contains(first))
        #expect(ticks.contains(second))
        ticks.removeAll()
        #expect(!ticks.contains(second))
    }
}
