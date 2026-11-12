import Foundation
import SwiftData

/// How the editor shows an exercise logged left and right apart. A way of
/// looking at the sets: they are the same in both.
nonisolated enum SideLayout: String, CaseIterable, Identifiable, Codable {
    /// One side on screen, a switcher above it.
    case tabs
    /// Both sides in one list, in the order they are trained.
    case list

    /// What the setting is until it is changed: how it has always been.
    static let standard = SideLayout.tabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tabs: return "Tabs"
        case .list: return "One List"
        }
    }
}

extension ExerciseSide {
    /// The side a new entry starts with: the one it started with the last
    /// time, read from the workouts themselves, or else left.
    static func suggested(lastLogged: ExerciseEntry?) -> ExerciseSide {
        lastLogged?.startSideRawValue.flatMap(ExerciseSide.init(rawValue:)) ?? .left
    }
}

/// The order of a unilateral entry. Left alone it follows from which side
/// starts and how many sets each side has: the sides take turns, and a side
/// with more sets runs on alone. Dragged in the list it is chosen freely and
/// each set says its place in `sideOrder`, every set or none. Tabs cannot
/// choose one and keep the one there is.
extension ExerciseEntry {
    /// The side it starts with; left where nothing was said.
    var startSide: ExerciseSide {
        startSideRawValue.flatMap(ExerciseSide.init(rawValue:)) ?? .left
    }

    /// The side it was said to start with, nil where nothing was. In a
    /// template nil is a choice: it starts as it did the last time.
    var statedStartSide: ExerciseSide? {
        startSideRawValue.flatMap(ExerciseSide.init(rawValue:))
    }

    /// Which rest ticking `set` off starts. A set number across both sides is
    /// one set, so when its other side is next and still to do, the rest is
    /// the one between sides; after that, as after any other set, the normal
    /// one. Same Weight has its own way there: its first tick.
    func restKind(after set: SetEntry) -> RestKind {
        guard unilateralMode == .perSide else { return .afterSet }
        let order = setsInOrder()
        guard let index = order.firstIndex(where: { $0.id == set.id }), order.indices.contains(index + 1) else {
            return .afterSet
        }
        let next = order[index + 1]
        return next.side != set.side && next.setNumber == set.setNumber && !next.isDone ? .betweenSides : .afterSet
    }

    /// Whether the order was chosen freely rather than following on its own.
    var hasChosenOrder: Bool {
        !sets.isEmpty && sets.allSatisfy { $0.sideOrder != nil }
    }

    /// The sets in the order they are trained. Without sides, simply in order.
    func setsInOrder() -> [SetEntry] {
        if hasChosenOrder {
            return sets.sorted { ($0.sideOrder ?? 0) < ($1.sideOrder ?? 0) }
        }
        let start = startSide.setSide
        return sets.sorted { first, second in
            if first.setNumber != second.setNumber { return first.setNumber < second.setNumber }
            return first.side == start && second.side != start
        }
    }

    /// Says which side starts, or in a template with nil that nothing is
    /// prescribed. In an order chosen freely that side's first set moves to
    /// the top, and the rest stays as it is.
    func setStartSide(_ side: ExerciseSide?) {
        startSideRawValue = side?.rawValue
        guard let side, hasChosenOrder else { return }
        var ordered = setsInOrder()
        guard let first = ordered.firstIndex(where: { $0.side == side.setSide }) else { return }
        ordered.insert(ordered.remove(at: first), at: 0)
        for (index, set) in ordered.enumerated() {
            set.sideOrder = index + 1
        }
    }

    /// Reorders the list of both sides, the way `List.onMove` reports it, and
    /// from here on the order is the one chosen. A set stays on its side and
    /// its side's numbers follow; the first set says which side starts.
    func moveSetsInList(from source: IndexSet, to destination: Int) {
        let current = setsInOrder()
        let moving = source.map { current[$0] }
        let before = current.enumerated().filter { $0.offset < destination && !source.contains($0.offset) }.map(\.element)
        let after = current.enumerated().filter { $0.offset >= destination && !source.contains($0.offset) }.map(\.element)
        let ordered = before + moving + after
        var numbers: [SetSide: Int] = [:]
        for (index, set) in ordered.enumerated() {
            set.sideOrder = index + 1
            numbers[set.side, default: 0] += 1
            set.setNumber = numbers[set.side] ?? 1
        }
        followChosenOrderWithStartSide()
    }

    /// In an order chosen freely, the side starting is the first set's.
    func followChosenOrderWithStartSide() {
        guard hasChosenOrder, let first = setsInOrder().first, first.side != .both else { return }
        startSideRawValue = first.side == .right ? ExerciseSide.right.rawValue : ExerciseSide.left.rawValue
    }

    /// What the workout's page says about it, nil where nothing was said:
    /// which side came first, and logged left and right the whole order.
    var sideOrderSummary: String? {
        switch unilateralMode {
        case .bilateral:
            return nil
        case .oneSided:
            return startSideRawValue == nil ? nil : "Started with \(startSide.title)"
        case .perSide:
            guard startSideRawValue != nil || hasChosenOrder else { return nil }
            let order = setsInOrder().map { ($0.side == .right ? "R" : "L") + "\($0.setNumber)" }
            return "Order: " + order.joined(separator: " · ")
        }
    }
}

extension WorkoutSession {
    /// A copy to train from. Which side an exercise starts with: what a
    /// template prescribes, or else the side of the last time, or else left.
    /// A workout copied is no prescription, only what happened once; its side
    /// comes into it only where there is no last time. An order chosen freely
    /// comes along as it is.
    func trainingCopy(dated date: Date, in context: ModelContext) -> WorkoutSession {
        let copy = copy(dated: date)
        let history = ExerciseHistory.fetch(in: context, excludingSession: copy.id)
        for entry in copy.exercises where entry.unilateralMode != .bilateral && !entry.hasChosenOrder {
            let lastTime = history.lastLogged(of: entry.identity)?.startSideRawValue
            let stated = entry.startSideRawValue
            entry.startSideRawValue = (isTemplate ? stated ?? lastTime : lastTime ?? stated) ?? ExerciseSide.left.rawValue
        }
        return copy
    }
}
