import Foundation
import SwiftData

/// What has been logged for each muscle group, read off everything ever logged.
///
/// An entry does not carry muscles of its own; they are read from the exercise
/// it was logged under, found by `ExerciseIdentity` the way `ExerciseHistory`
/// follows an exercise. So the muscles are the ones the exercise is filed under
/// today: refiling it moves its past workouts with it, and an entry whose
/// exercise was deleted — or never filed — counts for no muscle at all. Those
/// names are handed back as `unfiledNames`, so the screen can say what it
/// leaves out.
///
/// A set counts for every muscle of its exercise, kept apart by how: as a
/// main set for each main muscle, as a secondary set for each muscle it only
/// helps — a set of deadlifts is a main set for Glutes, Hamstrings and Back,
/// a secondary one for Quads. See `MuscleSets`; only the heat map's colour
/// weighs the two.
struct MuscleGroupHistory {
    /// One workout as a muscle's history shows it: the entries in it that
    /// train the muscle, in the workout's order.
    struct Workout: Identifiable {
        let session: WorkoutSession
        let entries: [ExerciseEntry]
        /// The entries' sets for the muscle, main and secondary.
        let sets: MuscleSets

        var id: UUID { session.id }
    }

    struct Week: Identifiable, Equatable {
        let start: Date
        let sets: MuscleSets

        var id: Date { start }
    }

    /// Every entry that belongs in a history — see `belongsInHistory` — and
    /// was saved with a workout.
    private let entries: [ExerciseEntry]
    /// The muscles of each exercise.
    private let targetsByIdentity: [ExerciseIdentity: MuscleTargets]

    /// With `categories`, only entries whose exercise is in one of them are
    /// read; everything after — counts, weeks, the first workout, the unfiled
    /// names — sees no other. The category, like the muscles, is the one the
    /// exercise carries today.
    init(entries: [ExerciseEntry], definitions: [ExerciseDefinition], categories: CategoryFilter? = nil) {
        var targets: [ExerciseIdentity: MuscleTargets] = [:]
        var categoryNames: [ExerciseIdentity: String] = [:]
        for definition in definitions {
            targets[definition.identity] = definition.muscleTargets
            categoryNames[definition.identity] = definition.categoryName
        }
        self.targetsByIdentity = targets
        self.entries = entries.filter { entry in
            guard entry.belongsInHistory, entry.session != nil, !entry.isInTemplate else { return false }
            guard let categories else { return true }
            return categories.includes(categoryName: categoryNames[entry.identity])
        }
    }

    func targets(of entry: ExerciseEntry) -> MuscleTargets {
        targetsByIdentity[entry.identity] ?? MuscleTargets(primary: [], secondary: [])
    }

    /// Every muscle the entry's exercise trains, main ones first.
    func muscles(of entry: ExerciseEntry) -> [MuscleGroup] {
        targets(of: entry).all
    }

    /// The entry's sets for `muscle`: main, secondary, or none.
    private func counted(_ entry: ExerciseEntry, for muscle: MuscleGroup) -> MuscleSets {
        let targets = targets(of: entry)
        if targets.primary.contains(muscle) { return MuscleSets(main: entry.setCount) }
        if targets.secondary.contains(muscle) { return MuscleSets(main: 0, secondary: entry.setCount) }
        return .zero
    }

    /// The workouts that trained `muscle`, newest first. A note on its own
    /// keeps a workout in the list, as it does in an exercise's history: that
    /// the exercise was skipped, and why, is part of the story.
    func workouts(training muscle: MuscleGroup) -> [Workout] {
        var bySession: [UUID: (session: WorkoutSession, entries: [ExerciseEntry])] = [:]
        for entry in entries where muscles(of: entry).contains(muscle) {
            guard let session = entry.session else { continue }
            bySession[session.id, default: (session, [])].entries.append(entry)
        }
        return bySession.values
            .map { session, entries in
                Workout(
                    session: session,
                    entries: entries.sorted { $0.orderIndex < $1.orderIndex },
                    sets: entries.reduce(.zero) { $0 + counted($1, for: muscle) }
                )
            }
            .sorted { $0.session.date > $1.session.date }
    }

    /// The sets for `muscle` in each of the last `count` weeks, oldest first,
    /// the last being the week of `now`. A week without any is there with a
    /// zero, so a gap shows as a gap.
    func weeks(
        training muscle: MuscleGroup,
        count: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Week] {
        guard count > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        else { return [] }

        var counts: [Date: MuscleSets] = [:]
        for entry in entries where muscles(of: entry).contains(muscle) {
            guard let date = entry.session?.date,
                  let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            else { continue }
            counts[week, default: .zero] = counts[week, default: .zero] + counted(entry, for: muscle)
        }

        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            return Week(start: start, sets: counts[start] ?? .zero)
        }
    }

    /// The sets for `muscle` in the week of `now` — the same week "This Week"
    /// on the workout list means.
    func setsThisWeek(training muscle: MuscleGroup, now: Date = .now, calendar: Calendar = .current) -> MuscleSets {
        weeks(training: muscle, count: 1, now: now, calendar: calendar).first?.sets ?? .zero
    }

    /// The sets for `muscle` from `start` on — everything, with no start.
    func setCount(training muscle: MuscleGroup, since start: Date?) -> MuscleSets {
        entries
            .filter { entry in
                guard let date = entry.session?.date else { return false }
                return (start.map { date >= $0 } ?? true) && muscles(of: entry).contains(muscle)
            }
            .reduce(.zero) { $0 + counted($1, for: muscle) }
    }

    /// The day of the first workout with anything in it, filed or not — where
    /// "all of it" begins.
    var firstWorkoutDate: Date? {
        entries.compactMap { $0.session?.date }.min()
    }

    /// The last time a set was logged for `muscle`. A note alone is not a
    /// muscle trained.
    func lastTrained(_ muscle: MuscleGroup) -> Date? {
        entries
            .filter { $0.hasLoggedData && muscles(of: $0).contains(muscle) }
            .compactMap { $0.session?.date }
            .max()
    }

    /// The exercises in the history that count for no muscle, because none is
    /// picked for them or their exercise is gone. Each name once, in the
    /// spelling of its newest entry, alphabetically.
    var unfiledNames: [String] {
        var names: [ExerciseIdentity: (name: String, date: Date)] = [:]
        for entry in entries where muscles(of: entry).isEmpty {
            let key = entry.identity
            let date = entry.session?.date ?? .distantPast
            if let known = names[key], known.date >= date { continue }
            names[key] = (entry.name.trimmingCharacters(in: .whitespacesAndNewlines), date)
        }
        return names.values.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
