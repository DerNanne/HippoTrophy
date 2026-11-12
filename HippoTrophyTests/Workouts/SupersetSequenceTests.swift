import Foundation
import Testing
@testable import HippoTrophy

/// The shared order of a superset's sets, and the set numbers counted from it.
@MainActor
struct SupersetSequenceTests {
    private typealias Slot = SupersetSequence.Slot

    private func ids(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

    private func letters(_ slots: [Slot]) -> String {
        slots.map { $0.member == .a ? "A" : "B" }.joined()
    }

    @Test func interleavesRoundByRoundAndPutsTheRestAtTheEnd() {
        #expect(letters(SupersetSequence.interleaved(a: ids(2), b: ids(2))) == "ABAB")
        #expect(letters(SupersetSequence.interleaved(a: ids(5), b: ids(3))) == "ABABABAA")
        #expect(letters(SupersetSequence.interleaved(a: ids(1), b: ids(3))) == "ABBB")
        #expect(SupersetSequence.interleaved(a: [], b: []).isEmpty)
    }

    @Test func interleavingKeepsEachExercisesOwnOrder() {
        let a = ids(3), b = ids(2)
        let slots = SupersetSequence.interleaved(a: a, b: b)
        #expect(slots.filter { $0.member == .a }.map(\.id) == a)
        #expect(slots.filter { $0.member == .b }.map(\.id) == b)
    }

    @Test func setNumbersCountWithinEachExercise() {
        let slots = SupersetSequence.interleaved(a: ids(4), b: ids(2))   // A B A B A A
        let numbers = SupersetSequence.numbering(slots)
        #expect(slots.map { numbers[$0.id]?.position } == [1, 2, 3, 4, 5, 6])
        #expect(slots.map { numbers[$0.id]?.setNumber } == [1, 1, 2, 2, 3, 4])
    }

    @Test func movingAcrossExercisesRenumbersBoth() {
        var slots = SupersetSequence.interleaved(a: ids(2), b: ids(2))  // A1 B1 A2 B2
        let b2 = slots[3]
        slots = SupersetSequence.moving(slots, from: IndexSet(integer: 3), to: 2)  // A1 B1 B2 A2
        #expect(letters(slots) == "ABBA")
        #expect(slots[2] == b2)
        let numbers = SupersetSequence.numbering(slots)
        #expect(slots.map { numbers[$0.id]?.setNumber } == [1, 1, 2, 2])
    }

    @Test func movingDownCountsTheDestinationBeforeTheMove() {
        let slots = SupersetSequence.interleaved(a: ids(2), b: ids(1))  // A B A
        let moved = SupersetSequence.moving(slots, from: IndexSet(integer: 0), to: 3)
        #expect(moved.map(\.id) == [slots[1].id, slots[2].id, slots[0].id])
    }

    @Test func aCopyLandsRightBehindItsSourceOrAtTheEnd() {
        let slots = SupersetSequence.interleaved(a: ids(2), b: ids(2))
        let copy = Slot(id: UUID(), member: .a)
        #expect(SupersetSequence.inserting(copy, after: slots[0].id, in: slots).map(\.id)
                == [slots[0].id, copy.id, slots[1].id, slots[2].id, slots[3].id])
        #expect(SupersetSequence.inserting(copy, after: nil, in: slots).last == copy)
        #expect(SupersetSequence.inserting(copy, after: UUID(), in: slots).last == copy)
    }

    @Test func leavingASetOutClosesItsGap() {
        var slots = SupersetSequence.interleaved(a: ids(3), b: ids(1))  // A B A A
        slots.remove(at: 1)
        let numbers = SupersetSequence.numbering(slots)
        #expect(slots.map { numbers[$0.id]?.position } == [1, 2, 3])
        #expect(slots.map { numbers[$0.id]?.setNumber } == [1, 2, 3])
    }
}
