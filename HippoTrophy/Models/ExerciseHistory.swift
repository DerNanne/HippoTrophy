import Foundation
import SwiftData

/// The questions the app asks of everything ever logged, answered in one place.
///
/// History follows the exercise's identity, not the definition: an entry
/// keeps what it was logged as — the catalog exercise's key, or the user's own
/// exercise's name — so the history of "Bench Press" is every entry with that
/// `ExerciseIdentity`, whatever became of the definition. What reaches into a
/// definition's own entries — sync on save, merging — asks by id instead.
///
/// Everything is fetched once and filtered in memory; a personal workout log
/// stays small enough for that, and it keeps the case-insensitive name match
/// out of a predicate.
///
/// A template's entries are in `entries` — a rename, a merge or a catalog
/// move reaches them like any other — but never in an answer about what was
/// trained.
struct ExerciseHistory {
    /// The entries asked about — every one in the store, templates' included,
    /// less the workout being looked at when there is one.
    let entries: [ExerciseEntry]

    /// - Parameter excludingSession: the workout on screen, which is not its
    ///   own history.
    init(entries: [ExerciseEntry], excludingSession sessionID: UUID? = nil) {
        self.entries = sessionID.map { id in entries.filter { $0.session?.id != id } } ?? entries
    }

    /// The entries of workouts trained: the history proper.
    private var trained: [ExerciseEntry] {
        entries.filter { !$0.isInTemplate }
    }

    static func fetch(in context: ModelContext, excludingSession sessionID: UUID? = nil) -> ExerciseHistory {
        let all = (try? context.fetch(FetchDescriptor<ExerciseEntry>())) ?? []
        return ExerciseHistory(entries: all, excludingSession: sessionID)
    }

    /// The exercises that have a history to open — see `belongsInHistory` for
    /// what counts.
    var identitiesWithHistory: Set<ExerciseIdentity> {
        Set(trained.filter(\.belongsInHistory).map(\.identity))
    }

    /// An exercise's history, newest first. One-sided and two-sided entries
    /// share the list: how an exercise is trained can be a phase rather than a
    /// different exercise, and splitting the two would cut exactly the run
    /// someone wants to follow.
    func entries(of identity: ExerciseIdentity) -> [ExerciseEntry] {
        trained
            .filter { $0.identity == identity && $0.belongsInHistory }
            .sorted { Self.date(of: $0) > Self.date(of: $1) }
    }

    /// The last time this exercise was measured. A note alone opens the
    /// history but is not a performance to beat.
    func lastLogged(of identity: ExerciseIdentity) -> ExerciseEntry? {
        trained
            .filter { $0.identity == identity && $0.hasLoggedData }
            .max { Self.date(of: $0) < Self.date(of: $1) }
    }

    /// "Last time" for every exercise at once — what the workout editor puts
    /// under each exercise.
    var lastPerformances: [ExerciseIdentity: LastPerformance] {
        var latest: [ExerciseIdentity: ExerciseEntry] = [:]
        for entry in trained where entry.hasLoggedData {
            let key = entry.identity
            if let known = latest[key], Self.date(of: known) >= Self.date(of: entry) { continue }
            latest[key] = entry
        }
        return latest.compactMapValues { LastPerformance(entry: $0) }
    }

    /// The entries logged from one definition, by id — templates' included,
    /// since whatever happens to the definition happens to them too.
    func entries(loggedFrom definitionID: UUID) -> [ExerciseEntry] {
        entries.filter { $0.definitionID == definitionID }
    }

    private static func date(of entry: ExerciseEntry) -> Date {
        entry.session?.date ?? .distantPast
    }
}

extension Sequence<ExerciseEntry> {
    /// How many workouts trained these entries are in — the count a warning
    /// names. Templates follow whatever is done to their exercise without
    /// being counted as workouts.
    var trainedWorkoutCount: Int {
        Set(filter { !$0.isInTemplate }.compactMap { $0.session?.id }).count
    }
}

extension ModelContext {
    /// Saves, and on failure hands back the message to show: `message`, then
    /// what went wrong. `nil` when the save went through. What to take back
    /// after a failure differs per caller, so that stays with the caller.
    func save(reporting message: String) -> String? {
        do {
            try save()
            return nil
        } catch {
            return Self.failureMessage(message, error)
        }
    }

    static func failureMessage(_ message: String, _ error: Error) -> String {
        "\(message)\n\n\(error.localizedDescription)"
    }
}
