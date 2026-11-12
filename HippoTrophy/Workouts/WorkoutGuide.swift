import Foundation

/// Where a workout being trained stands: which set comes next, and which
/// field of a set Next moves to. The editor follows it — it highlights, it
/// focuses, it scrolls — and decides nothing of this itself.
///
/// The order is the one sets are trained in: exercise after exercise, a
/// superset's two in their shared order.
enum WorkoutGuide {
    /// Every set of the workout in the order it is trained.
    static func order(of exercises: [ExerciseEntry]) -> [SetEntry] {
        let sorted = exercises.sorted { $0.orderIndex < $1.orderIndex }
        return ExerciseGrouping.groups(sorted).flatMap { group in
            SupersetPair(group)?.orderedSets ?? group.flatMap { $0.setsInOrder() }
        }
    }

    /// The set to do now: the first not done after the last one done, so a
    /// set passed over earlier does not hold the guide back. With nothing
    /// done after it, the first not done anywhere; nil once all are done.
    static func current(done: [Bool]) -> Int? {
        let start = (done.lastIndex(of: true) ?? -1) + 1
        return done[start...].firstIndex(of: false) ?? done.firstIndex(of: false)
    }

    /// The set after the one at `index` was done: the next not done after
    /// it, or else the first not done before it.
    static func next(after index: Int, done: [Bool]) -> Int? {
        guard done.indices.contains(index) else { return current(done: done) }
        return done[(index + 1)...].firstIndex(of: false) ?? done[..<index].firstIndex(of: false)
    }

    /// The field Next moves to from `field`, among a set's `fields` in
    /// order; nil from the last, where Next ticks the set off.
    static func field<ID: Equatable>(after field: ID, in fields: [ID]) -> ID? {
        guard let index = fields.firstIndex(of: field), fields.indices.contains(index + 1) else { return nil }
        return fields[index + 1]
    }

    /// The fields of a set the keyboard can type into, in order. A duration
    /// is picked on wheels, not typed, so the keyboard passes it.
    static func typedFields(of set: SetEntry) -> [FieldValue] {
        set.sortedValues.filter { $0.type != .time }
    }
}
