import Foundation

/// What an import would do, worked out before anything is written and
/// without a store in reach: the file on one side, a snapshot of what is on
/// the device on the other. Anything the planner cannot decide on its own
/// comes back as a question for the review step.
enum ImportPlanner {
    /// An exercise on the device, reduced to what the planner compares.
    struct Existing: Hashable {
        var id: UUID
        var record: ExerciseRecord
    }

    static func plan(
        file: BackupFile,
        existing: [Existing],
        knownWorkoutIDs: Set<UUID>,
        knownTemplateIDs: Set<UUID> = []
    ) -> ImportPlan {
        let candidates = existing.map { (identity: $0.record.identity, name: $0.record.name) }

        var items: [ExerciseItem] = []
        var seenInFile = Set<String>()
        for record in file.exercises ?? [] {
            let key = record.name.exerciseKey
            // A file that lists one name twice means one exercise; the first
            // spelling wins, as it does everywhere else.
            guard !key.isEmpty, seenInFile.insert(key).inserted else { continue }

            // A catalog exercise is found by its key, whatever it is called
            // on either side; failing that by name, an own exercise's own
            // kind first — see `ExerciseNaming.match`.
            guard let found = ExerciseNaming.match(identity: record.identity, name: record.name, among: candidates) else {
                items.append(ExerciseItem(record: record, outcome: .add))
                continue
            }
            let local = existing[found]
            guard local.record.shape == record.shape else {
                items.append(ExerciseItem(record: record, outcome: .conflict(local)))
                continue
            }
            let differences = differences(between: local.record, and: record)
            // A catalog exercise is the catalog's: the file cannot change its
            // details. Different details make the file's exercise one of its
            // own, if the user wants it — the same question as another
            // exercise under a taken name.
            if local.record.catalogKey != nil, !differences.isEmpty {
                items.append(ExerciseItem(record: record, outcome: .conflict(local)))
                continue
            }
            items.append(ExerciseItem(
                record: record,
                outcome: differences.isEmpty ? .same(local) : .review(local, differences)
            ))
        }

        let workouts = (file.workouts ?? []).map { record in
            WorkoutItem(record: record, isKnown: knownWorkoutIDs.contains(record.id))
        }
        let templates = (file.templates ?? []).map { record in
            TemplateItem(record: record, isKnown: knownTemplateIDs.contains(record.id))
        }
        return ImportPlan(
            exercises: items, workouts: workouts, templates: templates,
            gyms: file.gyms ?? [], machines: file.machines ?? []
        )
    }

    /// The ways two exercises of the same shape can still disagree. Each is a
    /// question with two answers, mine or the file's — or, against a catalog
    /// exercise, what makes the file's one of its own.
    static func differences(between local: ExerciseRecord, and file: ExerciseRecord) -> [Difference] {
        var result: [Difference] = []
        if local.category.exerciseKey != file.category.exerciseKey {
            result.append(.category(local: local.category, file: file.category))
        }
        // No muscles in the file means not filed yet there, not a different
        // filing: nothing to take over, so nothing to ask.
        if !file.muscleGroupNames.isEmpty, local.muscleFiling != file.muscleFiling {
            result.append(.muscles(local: local.muscleFiling, file: file.muscleFiling))
        }
        // How a catalog exercise is trained is the catalog's, and a file from
        // before format 11 could not even say it: nothing to ask.
        let localSides = ExerciseSides(rawValue: local.sides) ?? .either
        let fileSides = ExerciseSides(rawValue: file.sides) ?? .either
        if local.catalogKey == nil, localSides != fileSides {
            result.append(.sides(local: localSides, file: fileSides))
        }
        // Whether a catalog exercise can be assisted is the catalog's too.
        if local.catalogKey == nil, local.offersAssistance != file.offersAssistance {
            result.append(.assistance(local: local.offersAssistance, file: file.offersAssistance))
        }
        let localOrder = local.fields.map(\.label.exerciseKey)
        let fileOrder = file.fields.map(\.label.exerciseKey)
        if localOrder != fileOrder {
            result.append(.fieldOrder(local: local.fields.map(\.label), file: file.fields.map(\.label)))
        }
        return result
    }
}

struct ImportPlan {
    var exercises: [ImportPlanner.ExerciseItem]
    var workouts: [ImportPlanner.WorkoutItem]
    var templates: [ImportPlanner.TemplateItem] = []
    /// Brought in with anything else: a gym or machine of a name already
    /// here is that one, and gains the file's machines.
    var gyms: [GymRecord] = []
    var machines: [MachineRecord] = []

    /// Whether the review step has anything to ask.
    var needsReview: Bool {
        exercises.contains { $0.outcome.needsDecision }
    }
}

extension ImportPlanner {
    struct ExerciseItem: Identifiable {
        var id: String { record.name.exerciseKey }
        var record: ExerciseRecord
        var outcome: Outcome
    }

    enum Outcome {
        /// Nothing on the device under this name.
        case add
        /// The same exercise, attribute for attribute. Nothing to do.
        case same(Existing)
        /// The same exercise, disagreeing on things that are not its identity.
        case review(Existing, [Difference])
        /// Another exercise under the same name — different fields or a
        /// different kind. The user says whether to merge, rename or skip.
        case conflict(Existing)

        var needsDecision: Bool {
            switch self {
            case .add, .same: return false
            case .review, .conflict: return true
            }
        }
    }

    enum Difference: Hashable {
        case category(local: String, file: String)
        case muscles(local: MuscleFiling, file: MuscleFiling)
        case sides(local: ExerciseSides, file: ExerciseSides)
        /// Whether the exercise can be logged assisted.
        case assistance(local: Bool, file: Bool)
        case fieldOrder(local: [String], file: [String])
    }

    struct WorkoutItem {
        var record: WorkoutRecord
        /// A workout already here is history and is left exactly as it is.
        var isKnown: Bool
    }

    struct TemplateItem {
        var record: TemplateRecord
        /// A template already here stays as it is, edits since included: a
        /// second copy beside it would only be clutter.
        var isKnown: Bool
    }
}

// MARK: - Decisions

/// What the user answered in the review step, keyed by the exercise's name.
struct ImportDecisions {
    /// For every `.review` item: which side wins, per difference.
    var attributes: [String: [ImportPlanner.Difference: Side]] = [:]
    /// For every `.conflict` item.
    var conflicts: [String: ConflictResolution] = [:]

    enum Side: Hashable {
        case mine
        case file
    }

    enum ConflictResolution: Equatable {
        /// Import the file's exercise under another name; both exist afterwards.
        case rename(String)
        /// Leave the file's exercise out. Its logged entries attach to the
        /// exercise of that name already here, by name.
        case skip
        /// Fold the file's exercise into the one here, field by field.
        case merge(FieldMapping)
    }

    func side(for name: String, _ difference: ImportPlanner.Difference) -> Side {
        attributes[name.exerciseKey]?[difference] ?? .mine
    }

    func resolution(for name: String) -> ConflictResolution? {
        conflicts[name.exerciseKey]
    }
}
