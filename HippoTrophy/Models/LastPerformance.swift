import Foundation

/// What an exercise looked like the last time it was logged, condensed to the
/// one line the editor shows under its name.
///
/// It holds values rather than the `ExerciseEntry` it was read from: the editor
/// collects every summary once when it opens, and a stored entry could be
/// deleted underneath a reference that lives that long. Weights stay in
/// kilograms, the way everything is stored, so the line is rendered in whatever
/// unit is set at the moment it is drawn.
struct LastPerformance: Equatable {
    struct LoggedSet: Equatable {
        var side: SetSide
        var reps: Int
        var weightKg: Double
        /// The help of an assisted set, in place of the weight.
        var assistanceKg: Double? = nil
    }

    struct Field: Equatable {
        var label: String
        var text: String
    }

    var date: Date
    var mode: UnilateralMode
    var sets: [LoggedSet]
    var fields: [Field]

    /// `nil` when the entry holds nothing worth a line — a set list that is all
    /// zeroes reads as "not logged" rather than as a session at zero kilograms.
    init?(entry: ExerciseEntry) {
        guard let date = entry.session?.date else { return nil }

        // Weight training reads as sets; anything else as the values of the
        // last set, which for an exercise without sets is the only one.
        let logged = entry.doneSets
            .filter { $0.logsWeightAndReps }
            .compactMap { set -> LoggedSet? in
                let reps = set.reps ?? 0
                let weight = set.weightKg ?? 0
                let assistance = set.assistanceKg
                guard reps > 0 || weight > 0 || assistance != nil else { return nil }
                return LoggedSet(side: set.side, reps: reps, weightKg: weight, assistanceKg: assistance)
            }
        let filled = logged.isEmpty
            ? (entry.doneSets.last?.sortedValues ?? [])
                .filter { !$0.isEmpty }
                .map { Field(label: $0.label, text: $0.displayText(unit: .current)) }
            : []
        guard !filled.isEmpty || !logged.isEmpty else { return nil }
        self.init(date: date, mode: entry.unilateralMode, sets: logged, fields: filled)
    }

    private init(date: Date, mode: UnilateralMode, sets: [LoggedSet], fields: [Field]) {
        self.date = date
        self.mode = mode
        self.sets = sets
        self.fields = fields
    }

    /// The line itself, e.g. `3 days ago: 3×8 @ 60 kg`.
    func summary(unit: WeightUnit) -> String {
        "\(age(now: .now)): \(performance(unit: unit))"
    }

    /// The same line for VoiceOver, which would read `3×8 @ 60 kg` as a string
    /// of symbols.
    func spokenSummary(unit: WeightUnit) -> String {
        "Last time, \(age(now: .now)): \(spokenPerformance(unit: unit))"
    }

    /// What was done, without when — `3×8 @ 60 kg`. For a list that already
    /// says the date, like a muscle group's history.
    func performance(unit: WeightUnit) -> String {
        body(unit: unit, spoken: false)
    }

    func spokenPerformance(unit: WeightUnit) -> String {
        body(unit: unit, spoken: true)
    }

    /// How long ago it was, rather than when it was: standing in the gym, the
    /// question is whether this is last session's number or one from a training
    /// block that ended long ago, and "3 days ago" answers that without any
    /// counting. Past a couple of months the distance stops meaning anything and
    /// the date says more, so that is where it hands over.
    func age(now: Date, calendar: Calendar = .current) -> String {
        Self.age(of: date, now: now, calendar: calendar)
    }

    /// The same reading for any day — how long ago a muscle was last trained
    /// is the same question as how long ago an exercise was.
    static func age(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ..<0: return dateText(for: date)
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(CountFormat.text(days, "day", "days")) ago"
        case 14...62:
            let weeks = days / 7
            return "\(CountFormat.text(weeks, "week", "weeks")) ago"
        default: return dateText(for: date)
        }
    }

    /// Carries the year once the entry is old enough to be from another one.
    private static func dateText(for date: Date) -> String {
        let sameYear = Calendar.current.component(.year, from: date)
            == Calendar.current.component(.year, from: .now)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Sets first, then the fields, each part left out when it is empty.
    private func body(unit: WeightUnit, spoken: Bool) -> String {
        let fieldText = fields
            .map { spoken ? "\($0.label): \($0.text)" : "\($0.label) \($0.text)" }
            .joined(separator: spoken ? ", " : " · ")
        guard !sets.isEmpty else { return fieldText }
        let setText = setBody(unit: unit, spoken: spoken)
        return fields.isEmpty ? setText : "\(setText)\(spoken ? ", " : " · ")\(fieldText)"
    }

    private func setBody(unit: WeightUnit, spoken: Bool) -> String {
        switch mode {
        case .bilateral:
            return setList(sets, unit: unit, spoken: spoken)
        case .oneSided:
            // Both sides were trained, so the sets are written down once; only
            // the mode says the weight is what a single side moved.
            let list = setList(sets, unit: unit, spoken: spoken)
            return "\(list) per side"
        case .perSide:
            // Sides logged apart are the case where the two numbers differ, so
            // showing only one of them would hide exactly what was logged.
            let parts = [(SetSide.left, "L", "Left"), (SetSide.right, "R", "Right")]
                .compactMap { side, short, spokenName -> String? in
                    let sideSets = sets.filter { $0.side == side }
                    guard !sideSets.isEmpty else { return nil }
                    let list = setList(sideSets, unit: unit, spoken: spoken)
                    return spoken ? "\(spokenName): \(list)" : "\(short) \(list)"
                }
            // A dash between the sides, where the sets themselves are separated
            // by a mid-dot: with one separator for both, the point where the
            // left side ends and the right begins disappears into the line.
            return parts.isEmpty
                ? setList(sets, unit: unit, spoken: spoken)
                : parts.joined(separator: spoken ? ", " : " — ")
        }
    }

    /// Sets that ran the same reps at the same weight — or the same help —
    /// are folded into one term, which is how the sets get said out loud
    /// anyway: three by eight at sixty.
    private func setList(_ sets: [LoggedSet], unit: WeightUnit, spoken: Bool) -> String {
        var terms: [String] = []
        var index = sets.startIndex

        while index < sets.endIndex {
            let set = sets[index]
            let load = loadText(of: set, unit: unit)
            var count = 1
            var next = sets.index(after: index)
            while next < sets.endIndex,
                  sets[next].reps == set.reps,
                  loadText(of: sets[next], unit: unit) == load {
                count += 1
                next = sets.index(after: next)
            }
            terms.append(term(count: count, of: set, unit: unit, spoken: spoken))
            index = next
        }

        return terms.joined(separator: spoken ? ", " : " · ")
    }

    /// What two sets must share to fold into one term, as printed.
    private func loadText(of set: LoggedSet, unit: WeightUnit) -> String {
        set.assistanceKg.map { "assist " + unit.formatted(kilograms: $0) } ?? unit.formatted(kilograms: set.weightKg)
    }

    /// A weight of zero is left off rather than printed: bodyweight sets are
    /// logged that way, and `0 kg` claims a measurement that was never made.
    /// Help is printed whatever it is — `0 kg assist` was set on the machine.
    private func term(count: Int, of set: LoggedSet, unit: WeightUnit, spoken: Bool) -> String {
        let reps = set.reps
        let hasWeight = set.weightKg > 0

        if spoken {
            let base = "\(CountFormat.text(count, "set", "sets")) of \(reps)"
            if let assistance = set.assistanceKg {
                return "\(base) with \(unit.number(fromKilograms: assistance)) \(unit.spokenName) of assistance"
            }
            guard hasWeight else { return base }
            let value = unit.number(fromKilograms: set.weightKg)
            return "\(base) at \(value) \(unit.spokenName)"
        }

        let base = "\(count)×\(reps)"
        if let assistance = set.assistanceKg {
            return "\(base) @ \(unit.formatted(kilograms: assistance)) assist"
        }
        guard hasWeight else { return base }
        return "\(base) @ \(unit.formatted(kilograms: set.weightKg))"
    }
}
