import Foundation

/// The order a superset's sets were done in — the rules, on plain values.
///
/// A superset is two exercises, A above B, trained by switching between them.
/// Which set came when is one shared sequence: A, B, A, B — or A, B, A, B, A, A
/// when one exercise got more sets. The sequence is what is stored
/// (`SetEntry.supersetPosition`); each exercise's own set numbers are counted
/// from it, so history, "last time" and the report keep reading set numbers
/// and never learn that the sets were interleaved.
enum SupersetSequence {
    enum Member: Hashable {
        case a, b
    }

    struct Slot: Equatable {
        let id: UUID
        let member: Member
    }

    /// What a set holds once the sequence is written back.
    struct Numbering: Equatable {
        /// 1…n across both exercises.
        let position: Int
        /// 1…n within the set's own exercise.
        let setNumber: Int
    }

    /// A then B, round after round; whatever one exercise has beyond the
    /// other's count follows at the end, in its own order. How sets already
    /// logged come together when two exercises become a superset.
    static func interleaved(a: [UUID], b: [UUID]) -> [Slot] {
        var slots: [Slot] = []
        for index in 0..<max(a.count, b.count) {
            if index < a.count { slots.append(Slot(id: a[index], member: .a)) }
            if index < b.count { slots.append(Slot(id: b[index], member: .b)) }
        }
        return slots
    }

    /// Moves rows the way `List.onMove` reports it: `destination` is the
    /// index before which they land, counted in the sequence before the move.
    static func moving(_ slots: [Slot], from source: IndexSet, to destination: Int) -> [Slot] {
        let moving = source.sorted().map { slots[$0] }
        let before = slots.enumerated().filter { $0.offset < destination && !source.contains($0.offset) }.map(\.element)
        let after = slots.enumerated().filter { $0.offset >= destination && !source.contains($0.offset) }.map(\.element)
        return before + moving + after
    }

    /// `slot` right behind `anchorID` — a copied set next to its source — or
    /// at the end when there is no such slot.
    static func inserting(_ slot: Slot, after anchorID: UUID?, in slots: [Slot]) -> [Slot] {
        guard let anchorID, let index = slots.firstIndex(where: { $0.id == anchorID }) else {
            return slots + [slot]
        }
        var result = slots
        result.insert(slot, at: index + 1)
        return result
    }

    /// Positions and set numbers for a sequence, by set id. A deleted set
    /// simply is not in the sequence any more, which closes its gap.
    static func numbering(_ slots: [Slot]) -> [UUID: Numbering] {
        var counts: [Member: Int] = [:]
        var result: [UUID: Numbering] = [:]
        for (index, slot) in slots.enumerated() {
            counts[slot.member, default: 0] += 1
            result[slot.id] = Numbering(position: index + 1, setNumber: counts[slot.member] ?? 1)
        }
        return result
    }
}
