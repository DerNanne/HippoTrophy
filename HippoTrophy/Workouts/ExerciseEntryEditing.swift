import Foundation
import SwiftData

/// What the workout editor does to one entry's sets, apart from the view that
/// asks for it. Set numbers count per side, from 1, without gaps; every
/// operation here leaves them that way. The caller saves.
extension ExerciseEntry {
    /// The sets logged on one side, in order.
    func sets(on side: SetSide) -> [SetEntry] {
        sortedSets.filter { $0.side == side }
    }

    /// Appends a set on `side` with an empty value for every field. The fields
    /// come from the definition, logged the way the entry's help says; if the
    /// definition is gone, from the last set, so an orphaned entry can still
    /// grow.
    @discardableResult
    func addSet(on side: SetSide, definition: ExerciseDefinition?, in context: ModelContext) -> SetEntry {
        let template: [(key: String, label: String, type: String)]
        if let definition {
            template = definition.sortedFields.map {
                ($0.key, assistance.loggedLabel(for: $0.type, label: $0.label), assistance.loggedType(for: $0.type).rawValue)
            }
        } else {
            template = (sortedSets.last?.sortedValues ?? []).map { ($0.fieldKey, $0.label, $0.typeRawValue) }
        }

        // At the end of an order chosen freely; otherwise the order follows.
        let sideOrder = hasChosenOrder ? (sets.compactMap(\.sideOrder).max() ?? 0) + 1 : nil
        // Not done until something is entered or it is ticked off.
        let set = SetEntry(setNumber: (sets(on: side).last?.setNumber ?? 0) + 1, sideRawValue: side.rawValue, sideOrder: sideOrder, isDone: false, exercise: self)
        sets.append(set)
        context.insert(set)
        for (index, field) in template.enumerated() {
            let value = FieldValue(fieldKey: field.key, label: field.label, typeRawValue: field.type, orderIndex: index, set: set)
            set.values.append(value)
            context.insert(value)
        }
        return set
    }

    /// Removes a set and closes the gap in its side's numbering.
    func deleteSet(_ set: SetEntry, in context: ModelContext) {
        let side = set.side
        sets.removeAll { $0.id == set.id }
        context.delete(set)
        for (index, item) in sets(on: side).enumerated() {
            item.setNumber = index + 1
        }
        followChosenOrderWithStartSide()
    }

    /// Inserts a copy of `source` — effort and values included — right behind
    /// it, planned: the values are where the next set starts from.
    @discardableResult
    func copySet(_ source: SetEntry, in context: ModelContext) -> SetEntry {
        for set in sets(on: source.side) where set.setNumber > source.setNumber {
            set.setNumber += 1
        }
        if let sourceOrder = source.sideOrder {
            for set in sets where (set.sideOrder ?? 0) > sourceOrder {
                set.sideOrder? += 1
            }
        }

        let copy = SetEntry(
            setNumber: source.setNumber + 1,
            sideRawValue: source.sideRawValue,
            effortValue: source.effortValue,
            sideOrder: source.sideOrder.map { $0 + 1 },
            isDone: false,
            exercise: self
        )
        sets.append(copy)
        context.insert(copy)
        for value in source.sortedValues {
            let copied = FieldValue(
                fieldKey: value.fieldKey, label: value.label, typeRawValue: value.typeRawValue,
                orderIndex: value.orderIndex, textValue: value.textValue, numberValue: value.numberValue, set: copy
            )
            copy.values.append(copied)
            context.insert(copied)
        }
        return copy
    }

    /// Reorders one side's sets the way `List.onMove` reports it.
    func moveSets(on side: SetSide, from source: IndexSet, to destination: Int) {
        // `move(fromOffsets:toOffset:)` lives in SwiftUI; spelled out here so
        // the model does not import it.
        let current = sets(on: side)
        let moving = source.map { current[$0] }
        let before = current.enumerated().filter { $0.offset < destination && !source.contains($0.offset) }.map(\.element)
        let after = current.enumerated().filter { $0.offset >= destination && !source.contains($0.offset) }.map(\.element)
        let ordered = before + moving + after
        // In an order chosen freely the side keeps the places it has there.
        let places = current.compactMap(\.sideOrder).sorted()
        for (index, set) in ordered.enumerated() {
            set.setNumber = index + 1
            if places.count == ordered.count { set.sideOrder = places[index] }
        }
        followChosenOrderWithStartSide()
    }

    /// How many ratings a switch to `scale` would throw away: every rated set
    /// of this entry, since a rating does not carry over to another scale —
    /// "hard" is no number of reps in reserve. None for the scale it already
    /// has. Earlier workouts are other entries and are never touched.
    func ratingsDiscarded(bySwitchingTo scale: EffortScale) -> Int {
        guard scale != effortScale else { return 0 }
        return sets.filter { $0.effort != nil }.count
    }

    /// Rates this entry's sets on `scale` from now on, dropping every rating
    /// it holds — the caller asks first when `ratingsDiscarded` says there is
    /// something to lose. The same scale again changes nothing.
    func switchEffortScale(to scale: EffortScale) {
        guard scale != effortScale else { return }
        effortScale = scale
        for set in sets {
            set.effortValue = nil
        }
    }

    /// Switches the help, and every set's weight with it: help logged in place
    /// of the weight becomes the weight again, and the other way round. The
    /// number stays — the help is usually switched on before anything is
    /// typed, and a number typed under the wrong title is the one worth
    /// keeping. Nothing is deleted, so a switch can always be undone.
    func applyAssistance(_ assistance: Assistance) {
        guard assistance != self.assistance else { return }
        self.assistance = assistance
        for value in sets.flatMap(\.values) where value.type.fieldType == .weight {
            let type = assistance.loggedType(for: .weight)
            guard value.type != type else { continue }
            value.type = type
            value.label = assistance.loggedLabel(for: .weight, label: FieldType.weight.displayName)
        }
    }

    /// Both sides hold sets — the one case where leaving Left/Right loses
    /// which side a set belonged to.
    var holdsBothSides: Bool {
        let sides = Set(sets.map(\.side))
        return sides.contains(.left) && sides.contains(.right)
    }

    /// Moves the sets along with the mode, because each mode shows a different
    /// side and a set left on the wrong one would simply vanish from the screen.
    /// Nothing is deleted: a split log collapses into one list, a single list
    /// moves over to the left side.
    func applyMode(_ mode: UnilateralMode) {
        let previous = unilateralMode
        unilateralMode = mode
        if mode != .perSide {
            sets.forEach { $0.sideOrder = nil }
        }
        if mode == .bilateral {
            startSideRawValue = nil
        }

        switch (previous, mode) {
        case (.perSide, .perSide):
            break
        case (.perSide, _):
            // Left first, then right, so the merged list keeps the order the
            // sets were logged in rather than interleaving the two sides.
            let merged = sets(on: .left) + sets(on: .right)
            for (index, set) in merged.enumerated() {
                set.side = .both
                set.setNumber = index + 1
            }
        case (_, .perSide):
            for set in sortedSets where set.side == .both {
                set.side = .left
            }
        default:
            // Two-sided and one-sided both log onto `.both`; only the label moves.
            break
        }
    }
}
