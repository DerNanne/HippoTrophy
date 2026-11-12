import SwiftUI

// MARK: - Design tokens

/// The look of the exported report, kept apart from the app's own styling on
/// purpose: a PDF is printed matter and always reads light, whatever theme the
/// phone is in. The values come from the export design handoff.
enum ReportStyle {
    static let textPrimary = Color(red: 0.122, green: 0.161, blue: 0.216)   // #1F2937
    static let textSecondary = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    static let textTertiary = Color(red: 0.612, green: 0.639, blue: 0.686)  // #9CA3AF
    static let divider = Color(red: 0.898, green: 0.906, blue: 0.922)       // #E5E7EB
    static let headerRule = Color(red: 0.067, green: 0.094, blue: 0.153)    // #111827
    static let cardBackground = Color(red: 0.953, green: 0.957, blue: 0.965)// #F3F4F6
    static let accent = Color(red: 0.145, green: 0.388, blue: 0.922)        // #2563EB
    static let page = Color.white

    /// A4 rather than the mock's US Letter — the report is printed and mailed in
    /// the places this app is used.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    /// 0.6in, the handoff's print margin.
    static let margin: CGFloat = 43.2
    static var contentWidth: CGFloat { pageSize.width - 2 * margin }

    static let exerciseBlockSpacing: CGFloat = 20
}

// MARK: - Number formatting

enum ReportFormat {
    /// The app's one weight format, so the printout says what the screen says.
    static func weight(_ kilograms: Double, in unit: WeightUnit) -> String {
        unit.formatted(kilograms: kilograms)
    }

    /// What a set's weight column says: the weight, or the help logged in
    /// its place.
    static func load(of set: WorkoutReportData.LoggedSet, in unit: WeightUnit) -> String {
        set.assistanceKg.map { weight($0, in: unit) + " assist" } ?? weight(set.weightKg, in: unit)
    }

    /// Volumes run into the thousands, so they carry a group separator.
    static func volume(_ kilograms: Double, in unit: WeightUnit) -> String {
        number(unit.value(fromKilograms: kilograms), maxFractionDigits: 0) + " " + unit.symbol
    }

    static func count(_ value: Int) -> String {
        number(Double(value), maxFractionDigits: 0)
    }

    private static func number(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSNumber) ?? String(value)
    }
}

// MARK: - Report data

/// What the report needs from a workout, worked out once so the views stay pure
/// layout and the volume rules live in a single readable place.
///
/// It is built from values, not from the store: `init(session:unit:)` reads the
/// workout once, and everything after — the volume rules, the side split, the
/// layout and the pagination — works on what was read. So the report can be
/// tested without a store, and the renderer never measures objects that could
/// change underneath it.
struct WorkoutReportData {
    /// One set as the report prints it.
    struct LoggedSet: Identifiable, Equatable {
        let id: UUID
        let number: Int
        let side: SetSide
        let weightKg: Double
        let reps: Int
        /// `nil` when the set was not rated, or its entry rates nothing.
        let effort: SetEffort?
        /// The set's place in its superset's shared order, 1…n across both
        /// exercises; `nil` for an exercise trained on its own.
        let position: Int?
        /// The help of an assisted set, which has no weight and so adds
        /// nothing to a volume.
        var assistanceKg: Double? = nil

        var volume: Double { weightKg * Double(reps) }
    }

    /// A line of a set table: the set, and what its first column says — its
    /// number, or in a superset its exercise's letter with it (`A1`, `B1`).
    struct SetRow: Identifiable, Equatable {
        let label: String
        let set: LoggedSet
        /// Which of a superset's two exercises the set belongs to; `nil`
        /// outside a superset.
        let member: SupersetSequence.Member?

        var id: UUID { self.set.id }

        /// An exercise's own sets, numbered as they were logged.
        static func numbered(_ sets: [LoggedSet]) -> [SetRow] {
            sets.map { SetRow(label: "\($0.number)", set: $0, member: nil) }
        }
    }

    /// One exercise of the workout as read, before the report decides about it.
    struct Entry: SupersetGroupable {
        let id: UUID
        let name: String
        let notes: String
        var instructions: String = ""
        let mode: UnilateralMode
        /// Whether every set is weight and reps — the only kind the report prints.
        let logsWeightAndReps: Bool
        let effortScale: EffortScale
        /// Shared with the partner it was trained with as a superset.
        let supersetID: UUID?
        /// Only the sets that count — those with something logged, see
        /// `WorkoutSession.setCount`. An entry without any was not trained.
        let sets: [LoggedSet]
    }

    struct Exercise: Identifiable {
        let id: UUID
        let name: String
        let notes: String
        var instructions: String = ""
        let mode: UnilateralMode
        /// Sets shown in the single table, for `.bilateral` and `.oneSided`.
        let sets: [LoggedSet]
        let leftSets: [LoggedSet]
        let rightSets: [LoggedSet]
        /// The line right of the exercise name; nil when nothing was weighted.
        let volumeText: String?
        /// Whether the set tables show the effort column: not for an exercise
        /// that rated nothing, where it could only ever be empty — its place
        /// stays blank. One that rates but left a set unrated shows it, and
        /// that cell stays empty.
        let showsEffort: Bool
        /// The exercise it was trained with as a superset, when that one is
        /// not printed — so the reader knows the two went together.
        let supersetPartner: String?
        let unit: WeightUnit
    }

    /// Two exercises trained by switching between them, printed as one block:
    /// A, the one higher up in the workout, and B.
    struct Superset: Identifiable {
        let a: Exercise
        let b: Exercise
        /// Both exercises' sets in the order they were done.
        let rows: [SetRow]

        var id: UUID { a.id }

        /// The shared table has the effort column when either exercise rates.
        var showsEffort: Bool { a.showsEffort || b.showsEffort }
    }

    /// What the report prints, in the workout's order.
    enum Item: Identifiable {
        case exercise(Exercise)
        case superset(Superset)

        var id: UUID {
            switch self {
            case .exercise(let exercise): exercise.id
            case .superset(let superset): superset.id
            }
        }
    }

    let title: String
    let dateText: String
    let notes: String
    let exerciseCount: Int
    let setCount: Int
    let totalVolume: Double
    let items: [Item]
    /// Every printed exercise, a superset's two included, in printed order.
    let exercises: [Exercise]
    /// Trained exercises without weight and reps, which are not in the report
    /// yet. They are carried so the page can say so — a report that quietly
    /// drops part of a workout is worse than one that admits the gap.
    let skippedNames: [String]
    var skippedCount: Int { skippedNames.count }
    /// The scales the printed sets were rated on, in the order they first
    /// appear — what the legend has to explain. Empty when nothing printed
    /// was rated, and then there is no legend.
    let effortScales: [EffortScale]
    /// The unit the report prints in. Read once here rather than in the views,
    /// so a rendering cannot end up half in kilograms and half in pounds.
    let unit: WeightUnit

    /// Reads the workout out of the store — the one place the report touches it.
    init(session: WorkoutSession, unit: WeightUnit = .current) {
        let sorted = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        // A superset's sets take their places in the shared order from
        // `SupersetPair`, which the editor shows — so sets paired before they
        // had positions read the same way here.
        var positions: [UUID: Int] = [:]
        for group in ExerciseGrouping.groups(sorted) {
            guard let pair = SupersetPair(group) else { continue }
            for (index, set) in pair.orderedSets.enumerated() {
                positions[set.id] = index + 1
            }
        }
        let entries = sorted
            .map { entry in
                Entry(
                    id: entry.id,
                    name: entry.name,
                    notes: entry.notes,
                    instructions: entry.instructions,
                    mode: entry.unilateralMode,
                    logsWeightAndReps: entry.logsWeightAndReps,
                    effortScale: entry.effortScale,
                    supersetID: entry.supersetID,
                    sets: entry.sortedSets.filter(\.hasLoggedData).map { set in
                        LoggedSet(
                            id: set.id,
                            number: set.setNumber,
                            side: set.side,
                            weightKg: set.weightKg ?? 0,
                            reps: set.reps ?? 0,
                            effort: set.effort,
                            position: positions[set.id],
                            assistanceKg: set.assistanceKg
                        )
                    }
                )
            }
        self.init(name: session.name, date: session.date, notes: session.notes, entries: entries, unit: unit)
    }

    /// - Parameter entries: the workout's exercises in order, sets in order.
    init(name: String, date: Date, notes: String, entries: [Entry], unit: WeightUnit) {
        self.unit = unit
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmedName.isEmpty ? "Workout" : trimmedName
        dateText = date.formatted(date: .complete, time: .shortened)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // An exercise without a set that counts was not trained: it is neither
        // printed nor missed.
        let trained = entries.filter { !$0.sets.isEmpty }
        let logged = trained.filter { Self.isPrinted($0) }
        skippedNames = trained.filter { !Self.isPrinted($0) }.map(\.name)

        items = ExerciseGrouping.groups(entries).flatMap { Self.items(from: $0, unit: unit) }
        exercises = items.flatMap { item -> [Exercise] in
            switch item {
            case .exercise(let exercise): [exercise]
            case .superset(let superset): [superset.a, superset.b]
            }
        }
        exerciseCount = logged.count
        setCount = logged.reduce(0) { $0 + $1.sets.count }
        totalVolume = logged.reduce(0) { $0 + Self.totalVolume(of: $1) }
        var scales: [EffortScale] = []
        for scale in logged.flatMap(\.sets).compactMap(\.effort?.scale) where !scales.contains(scale) {
            scales.append(scale)
        }
        effortScales = scales
    }

    /// Trained, and weight and reps — what the report can print.
    private static func isPrinted(_ entry: Entry) -> Bool {
        !entry.sets.isEmpty && entry.logsWeightAndReps
    }

    /// One group of the workout as printed. A superset is one block when
    /// both its exercises are printed. When one is not, the other stands on
    /// its own — naming its partner if that was trained and only cannot be
    /// printed; a partner never trained leaves no trace.
    private static func items(from group: [Entry], unit: WeightUnit) -> [Item] {
        let printed = group.filter { isPrinted($0) }
        guard group.count == 2 else {
            return printed.map { .exercise(exercise(from: $0, unit: unit)) }
        }
        if printed.count == 2 {
            return [.superset(superset(a: printed[0], b: printed[1], unit: unit))]
        }
        return printed.map { entry in
            let partner = group.first { $0.id != entry.id && !$0.sets.isEmpty }
            return .exercise(exercise(from: entry, supersetPartner: partner?.name, unit: unit))
        }
    }

    /// Both exercises' sets by their place in the shared order; a set
    /// without one goes last, in the order it came.
    private static func superset(a: Entry, b: Entry, unit: WeightUnit) -> Superset {
        let tagged = a.sets.map { (set: $0, member: SupersetSequence.Member.a) }
            + b.sets.map { (set: $0, member: SupersetSequence.Member.b) }
        let ordered = tagged.enumerated()
            .sorted { ($0.element.set.position ?? .max, $0.offset) < ($1.element.set.position ?? .max, $1.offset) }
            .map(\.element)
        return Superset(
            a: exercise(from: a, unit: unit),
            b: exercise(from: b, unit: unit),
            rows: ordered.map { set, member in
                SetRow(label: member.letter + "\(set.number)" + sideSuffix(set.side), set: set, member: member)
            }
        )
    }

    /// A superset has one table, so a set logged for one side says which.
    private static func sideSuffix(_ side: SetSide) -> String {
        switch side {
        case .both: ""
        case .left: " L"
        case .right: " R"
        }
    }

    private static func exercise(from entry: Entry, supersetPartner: String? = nil, unit: WeightUnit) -> Exercise {
        let left = entry.sets.filter { $0.side == .left }
        let right = entry.sets.filter { $0.side == .right }
        let both = entry.sets.filter { $0.side == .both }

        return Exercise(
            id: entry.id,
            name: entry.name,
            notes: entry.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: entry.instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: entry.mode,
            sets: both,
            leftSets: left,
            rightSets: right,
            volumeText: volumeText(mode: entry.mode, both: both, left: left, right: right, unit: unit),
            showsEffort: entry.effortScale != .off,
            supersetPartner: supersetPartner,
            unit: unit
        )
    }

    private static func volume(of sets: [LoggedSet]) -> Double {
        sets.reduce(0) { $0 + $1.volume }
    }

    /// The volume actually moved, which is what the summary card adds up. A
    /// one-sided log holds one side's work and stands for two, so it counts twice;
    /// an L/R log already has both sides written down.
    private static func totalVolume(of entry: Entry) -> Double {
        switch entry.mode {
        case .bilateral, .perSide:
            return volume(of: entry.sets)
        case .oneSided:
            return volume(of: entry.sets) * 2
        }
    }

    /// How an exercise reports its own volume. Sides are never merged: the point
    /// of logging them apart is to see them apart.
    private static func volumeText(
        mode: UnilateralMode,
        both: [LoggedSet],
        left: [LoggedSet],
        right: [LoggedSet],
        unit: WeightUnit
    ) -> String? {
        switch mode {
        case .bilateral:
            let total = volume(of: both)
            guard total > 0 else { return nil }
            return "Volume \(ReportFormat.volume(total, in: unit))"
        case .oneSided:
            let perSide = volume(of: both)
            guard perSide > 0 else { return nil }
            return "Volume \(ReportFormat.volume(perSide, in: unit)) per side · "
                + "\(ReportFormat.volume(perSide * 2, in: unit)) total"
        case .perSide:
            let leftVolume = volume(of: left)
            let rightVolume = volume(of: right)
            guard leftVolume > 0 || rightVolume > 0 else { return nil }
            return "Volume L \(ReportFormat.volume(leftVolume, in: unit)) · R \(ReportFormat.volume(rightVolume, in: unit))"
        }
    }
}

extension SupersetSequence.Member {
    /// How the report names the two: A above, B below — the letters of the
    /// editor's "Add A" and "Add B".
    var letter: String {
        switch self {
        case .a: "A"
        case .b: "B"
        }
    }
}
