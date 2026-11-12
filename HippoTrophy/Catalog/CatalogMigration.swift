import Foundation

/// Which catalog exercise an own exercise could move to, and how its fields
/// would land there — the decisions behind the review of My Exercises.
///
/// Moving is a merge into the catalog exercise. A catalog exercise keeps its
/// fields, so an own exercise can move only where every one of its fields
/// finds a field of the same kind: no new fields, nothing dropped. Nor can a
/// two-sided exercise move into a one-sided one or back. Which one
/// it *is* stays the user's call; the names only rank the suggestions.
enum CatalogMigration {
    /// The way the own exercise's fields would map onto `target`, or nil when
    /// they cannot without adding a field. A field of the same title and kind
    /// is taken first, then any free one of the same kind.
    static func mapping(from own: ExerciseRecord, into target: ExerciseRecord) -> FieldMapping? {
        guard own.tracksSets == target.tracksSets else { return nil }
        // A one-sided exercise's entries do not belong in a two-sided one's
        // history, nor the other way round.
        guard (ExerciseSides(rawValue: own.sides) ?? .either).canMerge(into: ExerciseSides(rawValue: target.sides) ?? .either) else {
            return nil
        }
        var destinations: [String: FieldMapping.Destination] = [:]
        var taken = Set<String>()
        var unmatched: [FieldRecord] = []
        for field in own.fields {
            if let match = target.fields.first(where: {
                !taken.contains($0.key) && $0.type == field.type && $0.label.exerciseKey == field.label.exerciseKey
            }) {
                taken.insert(match.key)
                destinations[field.key] = .field(targetKey: match.key)
            } else {
                unmatched.append(field)
            }
        }
        for field in unmatched {
            guard let match = target.fields.first(where: { !taken.contains($0.key) && $0.type == field.type }) else {
                return nil
            }
            taken.insert(match.key)
            destinations[field.key] = .field(targetKey: match.key)
        }
        return FieldMapping(destinations: destinations)
    }

    /// The catalog exercises `own` could move to, best guess first: the ones
    /// sharing more words of the name ahead, then alphabetical. Only those it
    /// can move to without a new field are listed.
    static func targets(for own: ExerciseRecord, among catalog: [ExerciseRecord]) -> [ExerciseRecord] {
        let words = Self.words(own.name)
        let scored: [(record: ExerciseRecord, shared: Int)] = catalog
            .filter { mapping(from: own, into: $0) != nil }
            .map { (record: $0, shared: Self.words($0.name).intersection(words).count) }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.shared != rhs.shared { return lhs.shared > rhs.shared }
            return lhs.record.name.localizedStandardCompare(rhs.record.name) == .orderedAscending
        }
        return sorted.map(\.record)
    }

    /// Whether the review asks about `own`: it can move somewhere. A
    /// suggestion is not needed — "Bankdrücken" shares no word with Barbell
    /// Bench Press, and the user can search, or keep it as theirs. What can
    /// move nowhere, Cardio or a field of its own, is not asked about.
    static func isOpen(_ own: ExerciseRecord, among catalog: [ExerciseRecord]) -> Bool {
        catalog.contains { mapping(from: own, into: $0) != nil }
    }

    /// The targets that share a word of the name — what is worth suggesting
    /// unasked; the review lists the rest under Others.
    static func suggestions(for own: ExerciseRecord, among catalog: [ExerciseRecord]) -> [ExerciseRecord] {
        let words = Self.words(own.name)
        return targets(for: own, among: catalog).filter { !Self.words($0.name).isDisjoint(with: words) }
    }

    /// A name's words, compared the way names are: case and surrounding space
    /// do not count. "Push-Up" is "push" and "up".
    static func words(_ name: String) -> Set<String> {
        Set(name.exerciseKey.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

/// The own exercises the user chose to keep in the review, so it does not
/// bring them up again. Stored as one string of ids in the user defaults:
/// it is a preference about the review, not data about training, and is not
/// in a backup.
nonisolated struct KeptOwnExercises: Equatable {
    var ids: Set<UUID>

    init(stored: String) {
        ids = Set(stored.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var stored: String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }
}

/// Whether the review of My Exercises is put in front of the user at launch.
///
/// Pushy on purpose: much of what comes next hangs on catalog exercises, and
/// the testers' own ones would otherwise stay as they are. It asks while an
/// own exercise is still open — may be in the catalog, neither moved nor
/// kept — but not twice within `interval`, so reopening the app mid-workout
/// does not bring it up. It stops for good once the user said so, or once
/// `enoughMoved` exercises were moved: then the review was done, and what is
/// left is meant to be theirs.
nonisolated struct CatalogReviewPrompt: Equatable {
    static let interval: TimeInterval = 3 * 60 * 60
    static let enoughMoved = 3

    var pending: Int
    var moved: Int
    var dontShowAgain: Bool
    /// When it was last shown; nil if never.
    var lastShown: Date?

    func shouldShow(at now: Date) -> Bool {
        guard !dontShowAgain, pending > 0, moved < Self.enoughMoved else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= Self.interval
    }
}
