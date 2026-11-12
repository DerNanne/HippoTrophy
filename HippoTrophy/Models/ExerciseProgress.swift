import Foundation

/// What the progress graph of an exercise plots: one number per workout.
enum ProgressMetric: String, CaseIterable, Identifiable {
    /// The estimated one-rep max of the best set — see `ExerciseProgress.estimatedMax`.
    case estimatedMax
    /// The heaviest weight lifted for at least one rep — or, for an exercise
    /// that was assisted, the heaviest load, help counting below zero.
    case maxWeight
    /// Weight × reps over every set, the way the report adds it up.
    case volume
    /// The most reps in one set, whatever the weight — what is left to follow
    /// for an exercise logged without weight.
    case mostReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimatedMax: "Est. 1RM"
        case .maxWeight: "Max Weight"
        case .volume: "Volume"
        case .mostReps: "Most Reps"
        }
    }

    /// Whether the number is a weight, shown in the weight unit; otherwise it
    /// is a count of reps.
    var isWeight: Bool { self != .mostReps }

    /// A value of this metric in words, for the detail of a tapped point. An
    /// estimate is rounded to the whole unit: a decimal would claim a precision
    /// the formula does not have.
    func text(_ value: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        switch self {
        case .estimatedMax:
            let number = unit.value(fromKilograms: value)
                .formatted(.number.precision(.fractionLength(0)).grouping(.never).locale(locale))
            return "≈ \(number) \(unit.symbol)"
        case .maxWeight:
            return unit.formatted(kilograms: value, locale: locale)
        case .volume:
            let number = unit.value(fromKilograms: value)
                .formatted(.number.precision(.fractionLength(0)).locale(locale))
            return "\(number) \(unit.symbol)"
        case .mostReps:
            return CountFormat.text(Int(value), "rep", "reps")
        }
    }

    /// What the graph's footer says the number is, for a history with
    /// assisted sets in it or without.
    func explanation(countingAssistance: Bool = false) -> String {
        switch self {
        case .estimatedMax:
            return "The best set of each workout, as an estimated one-rep max: weight × (1 + reps ÷ 30). Warm-up sets do not pull it down."
                + (countingAssistance ? " Assisted sets are left out." : "")
        case .maxWeight:
            guard countingAssistance else { return "The heaviest weight of each workout, lifted for at least one rep." }
            return "The heaviest load of each workout, lifted for at least one rep. Help counts below zero: 20 kg of assistance is −20, bodyweight is 0."
        case .volume:
            return "Weight × reps, added up over every set of each workout. One-sided sets count one side, as logged."
                + (countingAssistance ? " Assisted sets add nothing." : "")
        case .mostReps:
            return "The most reps in a single set of each workout."
        }
    }
}

/// The progress of one exercise, decided from what was logged: which numbers
/// the graph can show, and the points it draws for each.
///
/// Only sets of weight training count — weight and reps, at least one rep.
/// Everything else an exercise logs is ignored here; a set without a rep was
/// not a lift. An assisted set counts too, its help as a load below zero: the
/// way from −35 kg over bodyweight to +10 kg is one line. That is the only
/// place the help is a negative number — what the one-rep max and the volume
/// add up is weight, and an assisted set has none.
///
/// Every workout gives one point per line. A workout that logged the exercise
/// twice still gives one: the best set is the best of both, and the volume is
/// what was moved in all of them. An L/R log draws a left and a right line,
/// since logging the sides apart is for seeing them apart. Everything else is
/// one line, and the point carries the mode it was logged in, so a switch
/// between two-sided and one-sided is marked rather than converted — a barbell
/// and a dumbbell per hand do not convert into each other.
struct ExerciseProgress {
    struct LoggedSet: Equatable {
        var side: SetSide
        var weightKg: Double
        var reps: Int
        /// The help, for an assisted set whose help was logged.
        var assistanceKg: Double? = nil
        /// The set in the store, for a history that marks it.
        var setID: UUID? = nil

        /// What the set put on the body to lift: the weight, or the help
        /// below zero.
        var loadKg: Double {
            assistanceKg.map { -$0 } ?? weightKg
        }
    }

    /// One exercise in one workout, as read from the store.
    struct Session: Equatable {
        var workoutID: UUID
        var date: Date
        var mode: UnilateralMode
        var sets: [LoggedSet]
    }

    struct Point: Identifiable, Equatable {
        var date: Date
        /// `.both` for the one line of a two-sided or one-sided log, `.left`
        /// or `.right` for the two lines of an L/R log.
        var line: SetSide
        var mode: UnilateralMode
        /// Kilograms for a weight metric, reps for `.mostReps`.
        var value: Double
        /// The set the value comes from; `nil` for the volume, which comes
        /// from all of them.
        var bestSet: LoggedSet?
        /// How many sets went into the point.
        var setCount: Int

        var id: String { "\(date.timeIntervalSinceReferenceDate)-\(line.rawValue)" }

        /// Where the value comes from: the set — `60 kg × 8` — or, for the
        /// volume, how many sets. `nil` for a set without weight, whose reps
        /// are already the value.
        func sourceText(unit: WeightUnit, locale: Locale = .current) -> String? {
            guard let bestSet else { return CountFormat.text(setCount, "set", "sets") }
            if let assistance = bestSet.assistanceKg {
                return "\(unit.formatted(kilograms: assistance, locale: locale)) assist × \(bestSet.reps)"
            }
            guard bestSet.weightKg > 0 else { return nil }
            return "\(unit.formatted(kilograms: bestSet.weightKg, locale: locale)) × \(bestSet.reps)"
        }
    }

    /// A personal record: the best set ever logged, and when.
    struct Record: Equatable {
        var date: Date
        var mode: UnilateralMode
        var set: LoggedSet
        /// `.left` or `.right` for a side's own record, `.both` otherwise.
        var side: SetSide = .both

        var id: String { "\(mode.logsPerSideWeight)-\(side.rawValue)" }

        /// The set as the record names it — `65 kg × 10`, or `12 reps` for
        /// a record without weight.
        func setText(unit: WeightUnit, locale: Locale = .current) -> String {
            guard set.weightKg > 0 else { return CountFormat.text(set.reps, "rep", "reps") }
            return "\(unit.formatted(kilograms: set.weightKg, locale: locale)) × \(set.reps)"
        }
    }

    let sessions: [Session]

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    /// The entries of an exercise's history, in any order. Entries without a
    /// workout have no date to stand at and are left out.
    init(entries: [ExerciseEntry]) {
        sessions = entries.compactMap { entry in
            guard let workout = entry.session else { return nil }
            let mode = entry.unilateralMode
            let sets = entry.doneSets
                .filter { Self.line(of: $0.side, in: mode) != nil && $0.logsWeightAndReps }
                .map { LoggedSet(side: $0.side, weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0, assistanceKg: $0.assistanceKg, setID: $0.id) }
            return Session(workoutID: workout.id, date: workout.date, mode: mode, sets: sets)
        }
    }

    /// The numbers worth offering, in the order the switcher shows them. A
    /// history without a single weighted set has nothing but reps to follow:
    /// a one-rep max, a top weight or a volume would all be a flat zero.
    /// Assisted sets give it a load to follow besides.
    var metrics: [ProgressMetric] {
        let lifts = sessions.flatMap(\.sets).filter(Self.isLift)
        guard !lifts.isEmpty else { return [] }
        if lifts.contains(where: { $0.weightKg > 0 }) {
            return [.estimatedMax, .maxWeight, .volume, .mostReps]
        }
        return countsAssistance ? [.maxWeight, .mostReps] : [.mostReps]
    }

    /// Whether any lift was assisted. Then bodyweight is a load too — zero,
    /// the point between help and weight — and the top load is a line that
    /// can run below zero.
    var countsAssistance: Bool {
        sessions.flatMap(\.sets).contains { Self.isLift($0) && $0.assistanceKg != nil }
    }

    /// The metric to show when `preferred` was picked last: that one when this
    /// exercise offers it, otherwise the first that it does.
    func metric(preferring preferred: ProgressMetric) -> ProgressMetric? {
        metrics.contains(preferred) ? preferred : metrics.first
    }

    /// The personal records: the heaviest weight lifted, and at the same
    /// weight the most reps. A tie left after that goes to the earlier set —
    /// it got there first, and repeating it is not a new record.
    ///
    /// Weight comes first: once a set with weight is logged, bodyweight sets
    /// set no record. Until then — a pull-up never done with a belt — the
    /// record is the most reps in one set without weight. A set with help
    /// sets none either way: help is not bodyweight.
    ///
    /// A weight shared by both sides and one side's weight are no measure of
    /// each other, so each has its own record, the one logged most recently
    /// first. Mostly there is just one. Empty without an unassisted lift.
    ///
    /// Once the sides were logged apart, each side has its own record, left
    /// before right: logging them apart is for seeing them apart. A set of the
    /// same weight on both sides counts for either.
    var records: [Record] {
        let logsSidesApart = sessions.contains { $0.mode == .perSide }
        var best: [RecordKey: Record] = [:]
        var lastLogged: [Bool: Date] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let perSide = session.mode.logsPerSideWeight
            for set in session.sets where Self.isLift(set) && set.assistanceKg == nil {
                for side in Self.recordSides(of: set.side, in: session.mode, logsSidesApart: logsSidesApart) {
                    let key = RecordKey(perSideWeight: perSide, side: side)
                    lastLogged[perSide] = session.date
                    // Compared by weight, then reps: a bodyweight set's weight
                    // is zero, so any weighted set beats it, and among
                    // bodyweight sets the reps decide.
                    if let record = best[key], (set.weightKg, set.reps) <= (record.set.weightKg, record.set.reps) {
                        continue
                    }
                    best[key] = Record(date: session.date, mode: session.mode, set: set, side: side)
                }
            }
        }
        return best
            .sorted {
                let (first, second) = (lastLogged[$0.key.perSideWeight]!, lastLogged[$1.key.perSideWeight]!)
                return first != second ? first > second : $0.key.side.order < $1.key.side.order
            }
            .map(\.value)
    }

    private struct RecordKey: Hashable {
        var perSideWeight: Bool
        var side: SetSide
    }

    /// Which records a set competes for: its own side in an L/R log, either
    /// side for a set of the same weight on both once the sides have records
    /// of their own, and the one record otherwise.
    private static func recordSides(of side: SetSide, in mode: UnilateralMode, logsSidesApart: Bool) -> [SetSide] {
        switch mode {
        case .bilateral: [.both]
        case .oneSided: logsSidesApart ? [.left, .right] : [.both]
        case .perSide: side == .both ? [] : [side]
        }
    }

    /// The points of one metric, oldest first. A workout whose sets give the
    /// metric nothing — only bodyweight sets for a weight metric — has no point
    /// rather than a zero.
    func points(for metric: ProgressMetric) -> [Point] {
        var groups: [Key: (date: Date, sets: [LoggedSet])] = [:]
        for session in sessions {
            for set in session.sets where Self.isLift(set) {
                guard let line = Self.line(of: set.side, in: session.mode) else { continue }
                let key = Key(workoutID: session.workoutID, line: line, mode: session.mode)
                groups[key, default: (session.date, [])].sets.append(set)
            }
        }

        return groups
            .compactMap { key, group in
                Self.point(for: metric, of: group.sets, countingAssistance: countsAssistance).map { value, best in
                    Point(date: group.date, line: key.line, mode: key.mode, value: value, bestSet: best, setCount: group.sets.count)
                }
            }
            .sorted { ($0.date, $0.line.order) < ($1.date, $1.line.order) }
    }

    /// The points of the workout closest to `date` — one per line, so an L/R
    /// log gives both sides. Empty when there are no points.
    static func points(nearest date: Date, in points: [Point]) -> [Point] {
        guard let nearest = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else {
            return []
        }
        return points.filter { $0.date == nearest.date }
    }

    /// The values the graph's vertical axis covers when it cannot work that
    /// out by itself: a single value, or one repeated — a range of nothing,
    /// which leaves the axis without a number. `nil` when the values spread,
    /// and the chart picks its own round bounds.
    static func valueDomain(of values: [Double]) -> ClosedRange<Double>? {
        guard let low = values.min(), let high = values.max(), low == high else { return nil }
        let margin = max(abs(high) * 0.1, 1)
        // Above zero the axis stops at zero; a load below it has no floor.
        let bottom = low >= 0 ? max(0, low - margin) : low - margin
        return bottom...(high + margin)
    }

    /// The dates the time axis covers when the workouts lie within a week of
    /// each other: a week around them, so the axis counts days rather than the
    /// hours of a single one. `nil` for a longer history.
    static func dateDomain(of dates: [Date]) -> ClosedRange<Date>? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let week: TimeInterval = 7 * 86_400
        guard last.timeIntervalSince(first) < week else { return nil }
        let middle = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
        return middle.addingTimeInterval(-week / 2)...middle.addingTimeInterval(week / 2)
    }

    /// The estimated one-rep max of a set, by Epley: weight × (1 + reps / 30).
    /// A single rep is its own max; the formula would add three percent to it.
    /// The estimate grows less reliable past a dozen reps, but a trend in a
    /// similar range of reps stays readable.
    static func estimatedMax(weightKg: Double, reps: Int) -> Double {
        reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    private struct Key: Hashable {
        var workoutID: UUID
        var line: SetSide
        var mode: UnilateralMode
    }

    private nonisolated static func isLift(_ set: LoggedSet) -> Bool {
        set.reps > 0
    }

    /// Which line a set is drawn on. The sets an entry's history shows are the
    /// ones it counts: left and right for an L/R log, the shared list
    /// otherwise.
    private static func line(of side: SetSide, in mode: UnilateralMode) -> SetSide? {
        switch (mode, side) {
        case (.perSide, .left), (.perSide, .right): side
        case (.bilateral, .both), (.oneSided, .both): .both
        default: nil
        }
    }

    private static func point(for metric: ProgressMetric, of sets: [LoggedSet], countingAssistance: Bool) -> (Double, LoggedSet?)? {
        let weighted = sets.filter { $0.weightKg > 0 }
        switch metric {
        case .estimatedMax:
            // The first set wins a tie: it is the one that got there first.
            let best = weighted.max { estimatedMax(weightKg: $0.weightKg, reps: $0.reps) < estimatedMax(weightKg: $1.weightKg, reps: $1.reps) }
            return best.map { (estimatedMax(weightKg: $0.weightKg, reps: $0.reps), $0) }
        case .maxWeight:
            // At the same load, the set with more reps is the better one to
            // show. With help in the history, every set has a load, bodyweight
            // too.
            let loaded = countingAssistance ? sets : weighted
            let best = loaded.max { ($0.loadKg, $0.reps) < ($1.loadKg, $1.reps) }
            return best.map { ($0.loadKg, $0) }
        case .volume:
            guard !weighted.isEmpty else { return nil }
            return (weighted.reduce(0) { $0 + $1.weightKg * Double($1.reps) }, nil)
        case .mostReps:
            // At the same reps, the heavier set is the better one to show.
            let best = sets.max { ($0.reps, $0.loadKg) < ($1.reps, $1.loadKg) }
            return best.map { (Double($0.reps), $0) }
        }
    }
}

private extension SetSide {
    /// Left before right when two points share a day, so the order is stable.
    var order: Int {
        switch self {
        case .both: 0
        case .left: 1
        case .right: 2
        }
    }
}
