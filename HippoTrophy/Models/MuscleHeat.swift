import Foundation

/// How far back the heat map looks. The cases run in the order the slider
/// shows them, longest on the left: sliding left looks further back, and the
/// far end takes in everything since the first workout.
nonisolated enum HeatMapPeriod: Int, CaseIterable, Identifiable {
    case all
    case year
    case sixMonths
    case threeMonths
    case month

    var id: Int { rawValue }

    /// Short enough to stand under a slider stop.
    var shortName: String {
        switch self {
        case .all: return "All"
        case .year: return "1Y"
        case .sixMonths: return "6M"
        case .threeMonths: return "3M"
        case .month: return "1M"
        }
    }

    var name: String {
        switch self {
        case .all: return "All Time"
        case .year: return "Last Year"
        case .sixMonths: return "Last 6 Months"
        case .threeMonths: return "Last 3 Months"
        case .month: return "Last Month"
        }
    }

    private var months: Int? {
        switch self {
        case .all: return nil
        case .year: return 12
        case .sixMonths: return 6
        case .threeMonths: return 3
        case .month: return 1
        }
    }

    /// The first day counted: the same day so many months ago, from its
    /// start, so a workout on that morning is in. For `.all` it is the day of
    /// the first workout, or nothing when there is none.
    func start(now: Date, firstWorkout: Date?, calendar: Calendar = .current) -> Date? {
        guard let months else { return firstWorkout.map(calendar.startOfDay(for:)) }
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .month, value: -months, to: today)
    }
}

/// What the heat map shows: the sets each muscle group got in a period, and
/// the shade each one gets for it.
///
/// Shaded against the muscle group that got the most, the way the activity
/// grid shades a day against the busiest one, but without its steps (see
/// `HeatScale`). The question a heat map answers is where the training goes
/// and what it leaves out. The colour weighs a secondary set at half a main
/// one (`MuscleSets.weighted`), so a muscle that only helps does not look as
/// trained as the ones the exercises are for.
struct MuscleHeat {
    let start: Date?
    let sets: [MuscleGroup: MuscleSets]

    init(history: MuscleGroupHistory, period: HeatMapPeriod, now: Date = .now, calendar: Calendar = .current) {
        let start = period.start(now: now, firstWorkout: history.firstWorkoutDate, calendar: calendar)
        self.start = start
        var sets: [MuscleGroup: MuscleSets] = [:]
        for muscle in MuscleGroup.allCases {
            sets[muscle] = history.setCount(training: muscle, since: start)
        }
        self.sets = sets
    }

    var highest: Double {
        sets.values.map(\.weighted).max() ?? 0
    }

    func sets(for muscle: MuscleGroup) -> MuscleSets {
        sets[muscle] ?? .zero
    }

    /// The muscle group's sets as a share of the most trained one's, from 0
    /// for none to 1 for the most — what its colour is made from.
    func share(for muscle: MuscleGroup) -> Double {
        guard highest > 0 else { return 0 }
        return sets(for: muscle).weighted / highest
    }

    /// The quartile the muscle group falls in. The colour no longer steps
    /// with it, but "most trained" in the spoken summary still means the top
    /// quarter, not only the single group at the very top.
    func level(for muscle: MuscleGroup) -> Int {
        QuartileLevel.level(sets(for: muscle).weighted, highestCount: highest)
    }
}
