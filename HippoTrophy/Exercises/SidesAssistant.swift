import Foundation

/// The decisions behind the sides assistant: every own exercise left
/// undecided after the update becomes bilateral or unilateral, and what
/// happens to what was logged under it.
///
/// An exercise logged one way only — bilateral throughout, or one side at a
/// time throughout, or never — is sorted as a whole. One logged both ways is
/// decided entry by entry, each set to how it was logged to begin with: if
/// all end up on one side, the exercise takes that side; otherwise it splits,
/// keeping its name for the bilateral entries and handing the others to a
/// new "<name> (Unilateral)".
///
/// An entry that changes side changes mode: bilateral becomes Same Weight,
/// Same Weight becomes bilateral, and left/right becomes bilateral by
/// merging the two lists — the one change that cannot be taken back.
nonisolated struct SidesAssistant {
    struct Entry: Identifiable, Equatable {
        var id: UUID
        var mode: UnilateralMode
        var date: Date
        var workout: String
        var sets: Int
    }

    struct Exercise: Identifiable, Equatable {
        var id: UUID
        var name: String
        var muscleGroupNames: [String]
        /// Newest first.
        var entries: [Entry]

        /// Logged bilateral and one side at a time. Same Weight and left/right
        /// together are one way: one side at a time.
        var isMixed: Bool {
            let sides = Set(entries.map(Self.side(of:)))
            return sides.count > 1
        }

        static func side(of entry: Entry) -> ExerciseSides {
            entry.mode == .bilateral ? .both : .one
        }

        /// How it was logged, in counts: "2× Bilateral, 3× L/R".
        var history: String {
            guard !entries.isEmpty else { return "Never logged" }
            return UnilateralMode.allCases.compactMap { mode in
                let count = entries.filter { $0.mode == mode }.count
                return count > 0 ? "\(count)× \(mode.shortTitle)" : nil
            }.joined(separator: ", ")
        }
    }

    /// What deciding does to one exercise.
    struct Outcome: Equatable {
        /// What the exercise becomes.
        var sides: ExerciseSides
        /// Entries whose mode changes, and to what.
        var modes: [UUID: UnilateralMode] = [:]
        /// Entries that go to the new unilateral exercise; empty unless it
        /// splits.
        var split: Set<UUID> = []
        /// Left/right entries made bilateral, their two lists merged.
        var mergedLeftRight = 0
        /// Entries deleted, sets and all.
        var deletions: Set<UUID> = []
    }

    var exercises: [Exercise]
    /// The side picked for an exercise logged one way only.
    var choices: [UUID: ExerciseSides] = [:]
    /// The side of each entry of an exercise logged both ways.
    var entrySides: [UUID: ExerciseSides] = [:]
    /// The exercises logged both ways that were opened. Each starts decided,
    /// but is looked at before Done: the split it makes by itself is easy
    /// to miss from the first page.
    var opened: Set<UUID> = []
    /// Entries to delete on Done — something tried out, not trained.
    var deleted: Set<UUID> = []

    init(exercises: [Exercise]) {
        self.exercises = exercises
        for exercise in exercises where exercise.isMixed {
            for entry in exercise.entries {
                entrySides[entry.id] = Exercise.side(of: entry)
            }
        }
    }

    var uniform: [Exercise] { exercises.filter { !$0.isMixed } }
    var mixed: [Exercise] { exercises.filter(\.isMixed) }

    /// Every exercise has a side — the mixed ones start decided — and every
    /// mixed one was opened.
    var isComplete: Bool {
        uniform.allSatisfy { choices[$0.id] != nil } && mixed.allSatisfy { opened.contains($0.id) }
    }

    mutating func markOpened(_ exercise: Exercise) {
        opened.insert(exercise.id)
    }

    /// Marks an entry for deleting on Done, or takes the mark back.
    mutating func toggleDeleted(_ entry: Entry) {
        if deleted.contains(entry.id) {
            deleted.remove(entry.id)
        } else {
            deleted.insert(entry.id)
        }
    }

    mutating func decideAll(of exercise: Exercise, as sides: ExerciseSides) {
        for entry in exercise.entries {
            entrySides[entry.id] = sides
        }
    }

    /// Every entry back to how it was logged — where a mixed exercise starts
    /// — none of them deleted.
    mutating func resetAsLogged(_ exercise: Exercise) {
        for entry in exercise.entries {
            entrySides[entry.id] = Exercise.side(of: entry)
            deleted.remove(entry.id)
        }
    }

    /// Whether any entry is set otherwise than it was logged, or deleted.
    func isChanged(_ exercise: Exercise) -> Bool {
        exercise.entries.contains { entrySides[$0.id] != Exercise.side(of: $0) || deleted.contains($0.id) }
    }

    /// What deciding means for `exercise`, or nil while it has no side yet.
    func outcome(for exercise: Exercise) -> Outcome? {
        let sideOf: (Entry) -> ExerciseSides?
        if exercise.isMixed {
            sideOf = { entrySides[$0.id] }
        } else {
            guard let chosen = choices[exercise.id] else { return nil }
            sideOf = { _ in chosen }
        }

        var outcome = Outcome(sides: .both)
        outcome.deletions = Set(exercise.entries.map(\.id)).intersection(deleted)
        let kept = exercise.entries.filter { !deleted.contains($0.id) }
        var sides = Set<ExerciseSides>()
        for entry in kept {
            guard let side = sideOf(entry) else { return nil }
            sides.insert(side)
            switch (entry.mode, side) {
            case (.bilateral, .one):
                outcome.modes[entry.id] = .oneSided
            case (.oneSided, .both):
                outcome.modes[entry.id] = .bilateral
            case (.perSide, .both):
                outcome.modes[entry.id] = .bilateral
                outcome.mergedLeftRight += 1
            default:
                break
            }
        }
        if kept.isEmpty, let chosen = choices[exercise.id] {
            sides = [chosen]
        }
        if sides.count > 1 {
            outcome.sides = .both
            outcome.split = Set(kept.filter { sideOf($0) == .one }.map(\.id))
        } else {
            outcome.sides = sides.first ?? .both
        }
        return outcome
    }

    /// What the outcome says in words, a line each; warnings flagged.
    static func summary(of outcome: Outcome, name: String) -> [(text: String, isWarning: Bool)] {
        var lines: [(text: String, isWarning: Bool)] = []
        if !outcome.deletions.isEmpty {
            lines.append(("\(CountFormat.text(outcome.deletions.count, "entry is deleted, with all its sets", "entries are deleted, with all their sets")).", true))
        }
        let toSameWeight = outcome.modes.values.filter { $0 == .oneSided }.count
        let toBilateral = outcome.modes.values.filter { $0 == .bilateral }.count - outcome.mergedLeftRight
        if !outcome.split.isEmpty {
            let moving = CountFormat.text(outcome.split.count, "entry moves", "entries move")
            lines.append(("\(moving) to \(SideMigration.ownVariantName(of: name)).", false))
        }
        if toSameWeight > 0 {
            lines.append(("\(CountFormat.text(toSameWeight, "entry becomes", "entries become")) Unilateral, Same Weight.", false))
        }
        if toBilateral > 0 {
            lines.append(("\(CountFormat.text(toBilateral, "entry becomes", "entries become")) Bilateral.", false))
        }
        if outcome.mergedLeftRight > 0 {
            let merged = CountFormat.text(outcome.mergedLeftRight, "entry logged L/R becomes", "entries logged L/R become")
            lines.append(("\(merged) Bilateral: left and right are merged into one list.", true))
        }
        return lines
    }
}
