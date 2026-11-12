import Foundation
import SwiftData

/// One row of an exercise entry: the values of every field the exercise has,
/// plus which side it was done on and how hard it felt. An exercise that does
/// not track sets logs exactly one of these.
///
/// How hard it felt is a bare number, `nil` until rated; what the number
/// means is the entry's scale to say — see `EffortScale`.
///
/// A set is done or only planned — see `isDone`. A planned set keeps its
/// values, so a workout shows what was meant and not done; nothing counts it.
@Model
final class SetEntry {
    var id: UUID
    var setNumber: Int
    var sideRawValue: String
    var effortValue: Double?
    /// Where this set falls in its superset's shared order, 1…n across both
    /// exercises; `nil` outside a superset. Inside one it is the truth the set
    /// number is counted from — see `SupersetSequence`.
    var supersetPosition: Int?
    /// Where this set falls across both sides of an entry logged left and
    /// right, once that order was chosen freely in the list; nil while it
    /// follows from the start side and how many sets each side has. See
    /// `ExerciseEntry.setsInOrder`. Added in `SchemaV14`.
    var sideOrder: Int?
    /// Whether the set was trained. Values from a template or a copied
    /// workout are a plan until the set is ticked off — by its tick, or by
    /// Next after its last value. Added in `SchemaV8`, true for
    /// everything before: every set logged then was done.
    var isDone: Bool = true
    @Relationship(deleteRule: .cascade, inverse: \FieldValue.set)
    var values: [FieldValue]
    var exercise: ExerciseEntry?

    init(
        setNumber: Int,
        sideRawValue: String = SetSide.both.rawValue,
        effortValue: Double? = nil,
        supersetPosition: Int? = nil,
        sideOrder: Int? = nil,
        isDone: Bool = true,
        values: [FieldValue] = [],
        exercise: ExerciseEntry? = nil
    ) {
        self.id = UUID()
        self.setNumber = setNumber
        self.sideRawValue = sideRawValue
        self.effortValue = effortValue
        self.supersetPosition = supersetPosition
        self.sideOrder = sideOrder
        self.isDone = isDone
        self.values = values
        self.exercise = exercise
    }

    /// The rating, read through the entry's scale. A set without an entry has
    /// no scale and so no rating.
    var effort: SetEffort? {
        get { exercise?.effortScale.effort(storedAs: effortValue) }
        set { effortValue = newValue?.storedValue }
    }

    var side: SetSide {
        get { SetSide(rawValue: sideRawValue) ?? .both }
        set { sideRawValue = newValue.rawValue }
    }

    var sortedValues: [FieldValue] {
        values.sorted { $0.orderIndex < $1.orderIndex }
    }

    func value(of type: FieldType) -> FieldValue? {
        values.first { $0.type == type }
    }

    /// The weight in kilograms, when this set has a weight field with a value.
    var weightKg: Double? {
        value(of: .weight)?.numberValue
    }

    /// The help in kilograms, when this set was assisted and the help logged.
    var assistanceKg: Double? {
        value(of: .assistance)?.numberValue
    }

    var reps: Int? {
        value(of: .reps)?.numberValue.map { Int($0) }
    }

    /// Whether this is a set of weight training: both standard fields present,
    /// whatever else the exercise logs — the weight, or the help logged in its
    /// place. Volume and the report rest on this; an assisted set has no
    /// `weightKg` and adds nothing to a volume, like one at bodyweight.
    var logsWeightAndReps: Bool {
        (value(of: .weight) != nil || value(of: .assistance) != nil) && value(of: .reps) != nil
    }

    /// Whether anything was entered in this set, done or planned — what a
    /// row shows. Whether it counts is `hasLoggedData`.
    var hasValues: Bool {
        values.contains { !$0.isEmpty }
    }

    /// Whether the set counts as trained: done, and with a value in it. The
    /// one answer for every count, history and "last time" — a planned set
    /// is in none of them.
    var hasLoggedData: Bool {
        isDone && hasValues
    }
}
