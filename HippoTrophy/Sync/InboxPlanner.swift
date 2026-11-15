import Foundation

/// What the inbox can change, as it sees it: the templates by id and their
/// order, the archived ones in it too — `templateOrder`, which an archived
/// template keeps while it is away — the trained workouts by id, and the
/// user's own exercises by the id of their definition here. Desk knows an
/// exercise by its name; one name is one own exercise.
nonisolated struct InboxState: Equatable {
    var templates: [UUID: SyncTemplate]
    var order: [UUID]
    var workouts: [UUID: SyncWorkout]
    var exercises: [UUID: SyncExercise]

    init(templates: [SyncTemplate] = [], workouts: [SyncWorkout] = [], exercises: [UUID: SyncExercise] = [:]) {
        self.templates = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.order = templates.map(\.id)
        self.workouts = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.exercises = exercises
    }

    /// The own exercise of a name, found as `ExerciseIdentity` finds it.
    func ownExercise(named name: String) -> UUID? {
        exercises.first { $0.value.name.exerciseKey == name.exerciseKey }?.key
    }

    /// Whether a template or a workout has an entry of the own exercise of
    /// this name: then how its sets are logged is no longer free to change.
    func isInUse(_ name: String) -> Bool {
        let key = name.exerciseKey
        let entries = templates.values.flatMap(\.exercises) + workouts.values.flatMap(\.exercises)
        return entries.contains { $0.catalogKey == nil && $0.exercise.exerciseKey == key }
    }

    /// What renaming an own exercise does to its entries: they carry its
    /// name, as the exercise editor writes it onto them.
    mutating func renameEntries(from old: String, to new: String) {
        let key = old.exerciseKey
        func renamed(_ entries: [SyncEntry]) -> [SyncEntry] {
            entries.map { entry in
                guard entry.catalogKey == nil, entry.exercise.exerciseKey == key else { return entry }
                var entry = entry
                entry.exercise = new
                return entry
            }
        }
        templates = templates.mapValues { template in
            var template = template
            template.exercises = renamed(template.exercises)
            return template
        }
        workouts = workouts.mapValues { workout in
            var workout = workout
            workout.exercises = renamed(workout.exercises)
            return workout
        }
    }

    var inOrder: [SyncTemplate] { order.compactMap { templates[$0] } }

    /// The workouts by date, then id: an order that is the same every time.
    var workoutsByDate: [SyncWorkout] {
        workouts.values.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }
}

/// What the inbox comes to, worked out before anything is written: which
/// files apply, which wait in Desk for a decision, and the templates and
/// workouts after.
/// A file is one save in Desk, applied whole or not at all.
nonisolated enum InboxPlanner {
    struct File {
        var name: String
        var content: Result<InboxFile, InboxFile.ReadError>
    }

    enum Change: Equatable {
        case added(String)
        case changed(String)
        case archived(String)
        case restored(String)
        case deleted(String)
        case reordered
        case workoutAdded(String, Date)
        case workoutChanged(String, Date)
        case workoutDeleted(String, Date)
        case exerciseAdded(String)
        case exerciseChanged(String)
        case exerciseDeleted(String)
    }

    /// Why a file waits in Desk. Named by the template or workout it is about.
    enum Conflict: Equatable {
        /// Changed here since Desk read it.
        case changedHere(String)
        /// Deleted here since Desk read it.
        case deletedHere(String)
        /// A new template whose id is already one here, and not the same —
        /// only a copied file could do that.
        case alreadyHere(String)
        case workoutChangedHere(String, Date)
        case workoutDeletedHere(String, Date)
        case workoutAlreadyHere(String, Date)
        case exerciseChangedHere(String)
        case exerciseDeletedHere(String)
        /// A new name that is already one of the user's own exercises here.
        case exerciseNameTaken(String)
        /// How its sets are logged, changed while something is logged with
        /// it here: the iPhone's editor has to carry the sets along.
        case exerciseInUse(String)
    }

    enum Outcome: Equatable {
        case apply([Change])
        case conflict(Conflict)
        /// Written by a newer Desk: left in the inbox for an updated app.
        case tooNew(Int)
        /// Nothing this app can read; left where it is.
        case unreadable
    }

    struct Plan: Equatable {
        var outcomes: [(name: String, outcome: Outcome)]
        var result: InboxState

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.result == rhs.result && lhs.outcomes.map(\.name) == rhs.outcomes.map(\.name)
                && lhs.outcomes.map(\.outcome) == rhs.outcomes.map(\.outcome)
        }

        var changes: [Change] {
            outcomes.flatMap { item -> [Change] in
                if case .apply(let changes) = item.outcome { return changes }
                return []
            }
        }

        var conflicts: [Conflict] {
            outcomes.compactMap { item -> Conflict? in
                if case .conflict(let conflict) = item.outcome { return conflict }
                return nil
            }
        }
    }

    /// The files in their order — Desk names them by time, so by name — each
    /// on the state the ones before it left.
    static func plan(_ files: [File], on state: InboxState) -> Plan {
        var state = state
        var outcomes: [(name: String, outcome: Outcome)] = []
        for file in files.sorted(by: { $0.name < $1.name }) {
            switch file.content {
            case .failure(.tooNew(let version)):
                outcomes.append((file.name, .tooNew(version)))
            case .failure(.unreadable):
                outcomes.append((file.name, .unreadable))
            case .success(let inbox):
                var trial = state
                switch apply(inbox.operations, to: &trial) {
                case .success(let changes):
                    state = trial
                    outcomes.append((file.name, .apply(changes)))
                case .failure(let conflict):
                    outcomes.append((file.name, .conflict(conflict.conflict)))
                }
            }
        }
        return Plan(outcomes: outcomes, result: state)
    }

    private struct Refused: Error {
        var conflict: Conflict
    }

    private static func apply(_ operations: [SyncOperation], to state: inout InboxState) -> Result<[Change], Refused> {
        var changes: [Change] = []
        for operation in operations {
            switch operation {
            case .putTemplate(let template, let base):
                let current = state.templates[template.id]?.normalized
                let wanted = template.normalized
                if current == wanted { continue } // already so: a file applied twice changes nothing
                guard let base else {
                    // New in Desk.
                    if current != nil { return .failure(Refused(conflict: .alreadyHere(template.name))) }
                    state.templates[template.id] = wanted
                    state.order.insert(template.id, at: 0)
                    changes.append(.added(template.name))
                    continue
                }
                guard let current else { return .failure(Refused(conflict: .deletedHere(base.name))) }
                guard current == base.normalized else { return .failure(Refused(conflict: .changedHere(current.name))) }
                state.templates[template.id] = wanted
                changes.append(change(from: current, to: wanted))
            case .deleteTemplate(let id, let base):
                guard let current = state.templates[id]?.normalized else { continue } // gone already
                guard current == base.normalized else { return .failure(Refused(conflict: .changedHere(current.name))) }
                state.templates[id] = nil
                state.order.removeAll { $0 == id }
                changes.append(.deleted(current.name))
            case .putWorkout(let workout, let base):
                let current = state.workouts[workout.id]?.normalized
                let wanted = workout.normalized
                if current == wanted { continue }
                guard let base else {
                    if current != nil { return .failure(Refused(conflict: .workoutAlreadyHere(workout.name, workout.date))) }
                    state.workouts[workout.id] = wanted
                    changes.append(.workoutAdded(wanted.name, wanted.date))
                    continue
                }
                guard let current else { return .failure(Refused(conflict: .workoutDeletedHere(base.name, base.date))) }
                guard current == base.normalized else {
                    return .failure(Refused(conflict: .workoutChangedHere(current.name, current.date)))
                }
                state.workouts[workout.id] = wanted
                changes.append(.workoutChanged(wanted.name, wanted.date))
            case .deleteWorkout(let id, let base):
                guard let current = state.workouts[id]?.normalized else { continue }
                guard current == base.normalized else {
                    return .failure(Refused(conflict: .workoutChangedHere(current.name, current.date)))
                }
                state.workouts[id] = nil
                changes.append(.workoutDeleted(current.name, current.date))
            case .putExercise(let exercise, let base):
                guard let base else {
                    if let id = state.ownExercise(named: exercise.name) {
                        if state.exercises[id] == exercise { continue }
                        return .failure(Refused(conflict: .exerciseNameTaken(exercise.name)))
                    }
                    state.exercises[UUID()] = exercise
                    changes.append(.exerciseAdded(exercise.name))
                    continue
                }
                guard let id = state.ownExercise(named: base.name), let current = state.exercises[id] else {
                    // Renamed already: a file taken twice.
                    if let id = state.ownExercise(named: exercise.name), state.exercises[id] == exercise { continue }
                    return .failure(Refused(conflict: .exerciseDeletedHere(base.name)))
                }
                if current == exercise { continue }
                guard current == base else { return .failure(Refused(conflict: .exerciseChangedHere(current.name))) }
                if exercise.name.exerciseKey != base.name.exerciseKey, state.ownExercise(named: exercise.name) != nil {
                    return .failure(Refused(conflict: .exerciseNameTaken(exercise.name)))
                }
                if exercise.shape != base.shape, state.isInUse(base.name) {
                    return .failure(Refused(conflict: .exerciseInUse(base.name)))
                }
                state.exercises[id] = exercise
                if exercise.name != base.name {
                    state.renameEntries(from: base.name, to: exercise.name)
                }
                changes.append(.exerciseChanged(exercise.name))
            case .deleteExercise(let base):
                guard let id = state.ownExercise(named: base.name), let current = state.exercises[id] else { continue }
                guard current == base else { return .failure(Refused(conflict: .exerciseChangedHere(current.name))) }
                state.exercises[id] = nil
                changes.append(.exerciseDeleted(base.name))
            case .orderTemplates(let ids):
                // The order Desk gave for the templates it knew; one made here
                // since stays in front, as a new template stands first.
                let known = ids.filter { state.templates[$0] != nil }
                let unknown = state.order.filter { !ids.contains($0) }
                let order = unknown + known
                if order != state.order {
                    state.order = order
                    changes.append(.reordered)
                }
            }
        }
        return .success(changes)
    }

    /// Archiving is a change like any other, but says itself.
    private static func change(from old: SyncTemplate, to new: SyncTemplate) -> Change {
        var unarchived = new
        unarchived.archived = old.archived
        if unarchived == old, old.archived != new.archived {
            return new.archived ? .archived(new.name) : .restored(new.name)
        }
        return .changed(new.name)
    }
}

extension InboxPlanner.Change {
    var text: String {
        switch self {
        case .added(let name): "\(name) added"
        case .changed(let name): "\(name) changed"
        case .archived(let name): "\(name) archived"
        case .restored(let name): "\(name) back from the archive"
        case .deleted(let name): "\(name) deleted"
        case .reordered: "templates reordered"
        case .workoutAdded(let name, let date): "\(workoutLabel(name, date)) added"
        case .workoutChanged(let name, let date): "\(workoutLabel(name, date)) changed"
        case .workoutDeleted(let name, let date): "\(workoutLabel(name, date)) deleted"
        case .exerciseAdded(let name): "exercise \(name) added"
        case .exerciseChanged(let name): "exercise \(name) changed"
        case .exerciseDeleted(let name): "exercise \(name) deleted"
        }
    }
}

extension InboxPlanner.Conflict {
    var text: String {
        switch self {
        case .changedHere(let name): "\(name) was changed on this iPhone in the meantime"
        case .deletedHere(let name): "\(name) was deleted on this iPhone in the meantime"
        case .alreadyHere(let name): "\(name) is here already as another template"
        case .workoutChangedHere(let name, let date): "\(workoutLabel(name, date)) was changed on this iPhone in the meantime"
        case .workoutDeletedHere(let name, let date): "\(workoutLabel(name, date)) was deleted on this iPhone in the meantime"
        case .workoutAlreadyHere(let name, let date): "\(workoutLabel(name, date)) is here already as another workout"
        case .exerciseChangedHere(let name): "exercise \(name) was changed on this iPhone in the meantime"
        case .exerciseDeletedHere(let name): "exercise \(name) was deleted on this iPhone in the meantime"
        case .exerciseNameTaken(let name): "an exercise named \(name) is here already"
        case .exerciseInUse(let name): "\(name) has sets logged here now; how it logs them changes on the iPhone"
        }
    }
}

/// A workout as a line names it: its name and day — "Push of Nov 13" —
/// or "The workout of Nov 13" when it has no name.
nonisolated func workoutLabel(_ name: String, _ date: Date) -> String {
    let day = date.formatted(.dateTime.month(.abbreviated).day())
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "the workout of \(day)" : "\(trimmed) of \(day)"
}
