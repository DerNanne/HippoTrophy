import Foundation
import SwiftData

/// A superset's two entries, A above B, and what the workout editor does to
/// their sets. The rules are `SupersetSequence`'s; this reads the sets out of
/// the store and writes the result back — positions and set numbers together,
/// so they never disagree. The caller saves.
struct SupersetPair {
    let a: ExerciseEntry
    let b: ExerciseEntry

    /// `nil` unless there are exactly two entries. A is whichever comes first
    /// in the workout.
    init?(_ entries: [ExerciseEntry]) {
        guard entries.count == 2 else { return nil }
        let ordered = entries.sorted { $0.orderIndex < $1.orderIndex }
        a = ordered[0]
        b = ordered[1]
    }

    var entries: [ExerciseEntry] { [a, b] }

    func contains(_ entry: ExerciseEntry) -> Bool {
        entry.id == a.id || entry.id == b.id
    }

    func member(of set: SetEntry) -> SupersetSequence.Member {
        set.exercise?.id == b.id ? .b : .a
    }

    /// Every set of both, in the order they were done. Sets paired before
    /// they had positions — or any set missing one — read as interleaved
    /// rounds, which is what a superset means when nothing else is known;
    /// the first change writes that order down.
    var orderedSets: [SetEntry] {
        let all = a.sets + b.sets
        guard all.allSatisfy({ $0.supersetPosition != nil }) else {
            let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            return SupersetSequence.interleaved(a: a.sortedSets.map(\.id), b: b.sortedSets.map(\.id))
                .compactMap { byID[$0.id] }
        }
        return all.sorted { ($0.supersetPosition ?? 0) < ($1.supersetPosition ?? 0) }
    }

    private var slots: [SupersetSequence.Slot] {
        orderedSets.map { SupersetSequence.Slot(id: $0.id, member: member(of: $0)) }
    }

    /// Writes positions and set numbers for `slots` onto the sets.
    private func write(_ slots: [SupersetSequence.Slot]) {
        let numbers = SupersetSequence.numbering(slots)
        for set in a.sets + b.sets {
            guard let numbering = numbers[set.id] else { continue }
            set.supersetPosition = numbering.position
            set.setNumber = numbering.setNumber
        }
    }

    /// Brings the sets both already hold together: A, B, A, B, the rest at the
    /// end. What turning two exercises into a superset does.
    func interleaveExisting() {
        write(SupersetSequence.interleaved(a: a.sortedSets.map(\.id), b: b.sortedSets.map(\.id)))
    }

    @discardableResult
    func addSet(to entry: ExerciseEntry, definition: ExerciseDefinition?, in context: ModelContext) -> SetEntry {
        let current = slots
        let set = entry.addSet(on: .both, definition: definition, in: context)
        write(current + [SupersetSequence.Slot(id: set.id, member: member(of: set))])
        return set
    }

    func deleteSet(_ set: SetEntry, in context: ModelContext) {
        let remaining = slots.filter { $0.id != set.id }
        set.exercise?.sets.removeAll { $0.id == set.id }
        context.delete(set)
        write(remaining)
    }

    @discardableResult
    func copySet(_ source: SetEntry, in context: ModelContext) -> SetEntry? {
        guard let entry = source.exercise else { return nil }
        let current = slots
        let copy = entry.copySet(source, in: context)
        write(SupersetSequence.inserting(SupersetSequence.Slot(id: copy.id, member: member(of: copy)), after: source.id, in: current))
        return copy
    }

    /// Rows moved in the interleaved list, which is `orderedSets`.
    func moveSets(from source: IndexSet, to destination: Int) {
        write(SupersetSequence.moving(slots, from: source, to: destination))
    }

    /// The entry left behind when its partner goes is an exercise of its own
    /// again: its sets lose their positions and keep the numbers they have.
    static func dissolve(_ entry: ExerciseEntry) {
        entry.supersetID = nil
        for set in entry.sets {
            set.supersetPosition = nil
        }
    }
}
