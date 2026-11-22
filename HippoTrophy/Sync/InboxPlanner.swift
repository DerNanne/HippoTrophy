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
    /// Gyms and machines by their id here; Desk knows them by name.
    var gyms: [UUID: SyncGym]
    var machines: [UUID: SyncMachine]
    /// The catalog exercises by catalog key: what an own exercise can be
    /// merged into. Read only — nothing from Desk changes the catalog.
    var catalog: [String: SyncExercise]
    /// Own exercises merged away whose photo goes to the one they were
    /// merged into, if that has none: source id → target id. Not part of
    /// what Desk sees — the sync format carries no photos — and nothing the
    /// store says afterwards, so Undo leaves the photo where it went.
    var photoHandovers: [UUID: UUID] = [:]

    init(
        templates: [SyncTemplate] = [], workouts: [SyncWorkout] = [], exercises: [UUID: SyncExercise] = [:],
        gyms: [UUID: SyncGym] = [:], machines: [UUID: SyncMachine] = [:], catalog: [String: SyncExercise] = [:]
    ) {
        self.templates = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.order = templates.map(\.id)
        self.workouts = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.exercises = exercises
        self.gyms = gyms
        self.machines = machines
        self.catalog = catalog
    }

    func gym(named name: String) -> UUID? {
        gyms.first { $0.value.name.exerciseKey == name.exerciseKey }?.key
    }

    func machine(named name: String) -> UUID? {
        machines.first { $0.value.name.exerciseKey == name.exerciseKey }?.key
    }

    /// What renaming or deleting a gym does to the templates and workouts at
    /// it: they name it as it is now, or none.
    mutating func regym(from old: String, to new: String?) {
        let key = old.exerciseKey
        templates = templates.mapValues { template in
            var template = template
            if template.gym?.exerciseKey == key { template.gym = new }
            return template
        }
        workouts = workouts.mapValues { workout in
            var workout = workout
            if workout.gym?.exerciseKey == key { workout.gym = new }
            return workout
        }
    }

    /// The same for a machine: the entries done at it, and the gyms it stands in.
    mutating func remachine(from old: String, to new: String?) {
        let key = old.exerciseKey
        func moved(_ entries: [SyncEntry]) -> [SyncEntry] {
            entries.map { entry in
                guard entry.machine?.exerciseKey == key else { return entry }
                var entry = entry
                entry.machine = new
                return entry
            }
        }
        templates = templates.mapValues { template in
            var template = template
            template.exercises = moved(template.exercises)
            return template
        }
        workouts = workouts.mapValues { workout in
            var workout = workout
            workout.exercises = moved(workout.exercises)
            return workout
        }
        gyms = gyms.mapValues { gym in
            var gym = gym
            gym.machines = gym.machines.compactMap { $0.exerciseKey == key ? new : $0 }
            return gym
        }
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

    /// What merging an own exercise does to its entries, as
    /// `ExerciseMerging.attach` writes it onto them: they carry the target's
    /// name and catalog key, and every set its values under the keys the
    /// merge gave them, labelled and ordered as the target's fields, with an
    /// empty value for each field it had none for. A value under a key the
    /// target does not know stays where it was. The mapping pairs fields of
    /// one type only, so no value changes its type.
    mutating func moveEntries(of source: String, to target: String, catalogKey: String?, fields: [SyncField], keyRewrite: [String: String]) {
        let key = source.exerciseKey
        func moved(_ entries: [SyncEntry]) -> [SyncEntry] {
            entries.map { entry in
                guard entry.catalogKey == nil, entry.exercise.exerciseKey == key else { return entry }
                var entry = entry
                entry.exercise = target
                entry.catalogKey = catalogKey
                let assistance = Assistance(rawValue: entry.assistance) ?? .unassisted
                entry.sets = entry.sets.map { set in
                    var set = set
                    set.values = Self.aligned(set.values, to: fields, assistance: assistance, keyRewrite: keyRewrite)
                    return set
                }
                return entry
            }
        }
        templates = templates.mapValues { template in
            var template = template
            template.exercises = moved(template.exercises)
            return template
        }
        workouts = workouts.mapValues { workout in
            var workout = workout
            workout.exercises = moved(workout.exercises)
            return workout
        }
    }

    /// `ExerciseMerging.align` on a set's values as the format carries them:
    /// in their order, which is the store's `orderIndex`.
    private static func aligned(_ values: [SyncValue], to fields: [SyncField], assistance: Assistance, keyRewrite: [String: String]) -> [SyncValue] {
        var placed: [(index: Int, value: SyncValue)] = values.enumerated().map { index, value in
            var value = value
            if let key = keyRewrite[value.key] { value.key = key }
            return (index, value)
        }
        for (index, field) in fields.enumerated() {
            let type = FieldType(rawValue: field.type) ?? .text
            let loggedType = assistance.loggedType(for: type)
            let label = assistance.loggedLabel(for: type, label: field.label)
            if let at = placed.firstIndex(where: { $0.value.key == field.key }) {
                placed[at].value.label = label
                placed[at].index = index
            } else {
                placed.append((index, SyncValue(key: field.key, label: label, type: loggedType.rawValue, text: nil, number: nil)))
            }
        }
        return placed.enumerated()
            .sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }
            .map(\.element.value)
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
        case gymAdded(String)
        case gymChanged(String)
        case gymDeleted(String)
        case machineAdded(String)
        case machineChanged(String)
        case machineDeleted(String)
        case exerciseMerged(String, into: String)
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
        case gymChangedHere(String)
        case gymDeletedHere(String)
        case gymNameTaken(String)
        case machineChangedHere(String)
        case machineDeletedHere(String)
        case machineNameTaken(String)
        /// Two exercises that cannot be one, however Desk came to send it:
        /// another kind, sides that do not mix, a mapping that does not hold.
        case exerciseCannotMerge(String, into: String)
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
            case .putGym(let gym, let base):
                if let missing = gym.machines.first(where: { state.machine(named: $0) == nil }) {
                    return .failure(Refused(conflict: .machineDeletedHere(missing)))
                }
                guard let base else {
                    if let id = state.gym(named: gym.name) {
                        if state.gyms[id] == gym { continue }
                        return .failure(Refused(conflict: .gymNameTaken(gym.name)))
                    }
                    state.gyms[UUID()] = gym
                    changes.append(.gymAdded(gym.name))
                    continue
                }
                guard let id = state.gym(named: base.name), let current = state.gyms[id] else {
                    if let id = state.gym(named: gym.name), state.gyms[id] == gym { continue }
                    return .failure(Refused(conflict: .gymDeletedHere(base.name)))
                }
                if current == gym { continue }
                guard current == base else { return .failure(Refused(conflict: .gymChangedHere(current.name))) }
                if gym.name.exerciseKey != base.name.exerciseKey, state.gym(named: gym.name) != nil {
                    return .failure(Refused(conflict: .gymNameTaken(gym.name)))
                }
                state.gyms[id] = gym
                if gym.name != base.name { state.regym(from: base.name, to: gym.name) }
                changes.append(.gymChanged(gym.name))
            case .deleteGym(let base):
                guard let id = state.gym(named: base.name), let current = state.gyms[id] else { continue }
                guard current == base else { return .failure(Refused(conflict: .gymChangedHere(current.name))) }
                state.gyms[id] = nil
                state.regym(from: base.name, to: nil)
                changes.append(.gymDeleted(base.name))
            case .putMachine(let machine, let base):
                guard let base else {
                    if let id = state.machine(named: machine.name) {
                        if state.machines[id] == machine { continue }
                        return .failure(Refused(conflict: .machineNameTaken(machine.name)))
                    }
                    state.machines[UUID()] = machine
                    changes.append(.machineAdded(machine.name))
                    continue
                }
                guard let id = state.machine(named: base.name), let current = state.machines[id] else {
                    if let id = state.machine(named: machine.name), state.machines[id] == machine { continue }
                    return .failure(Refused(conflict: .machineDeletedHere(base.name)))
                }
                if current == machine { continue }
                guard current == base else { return .failure(Refused(conflict: .machineChangedHere(current.name))) }
                if machine.name.exerciseKey != base.name.exerciseKey, state.machine(named: machine.name) != nil {
                    return .failure(Refused(conflict: .machineNameTaken(machine.name)))
                }
                state.machines[id] = machine
                state.remachine(from: base.name, to: machine.name)
                changes.append(.machineChanged(machine.name))
            case .deleteMachine(let base):
                guard let id = state.machine(named: base.name), let current = state.machines[id] else { continue }
                guard current == base else { return .failure(Refused(conflict: .machineChangedHere(current.name))) }
                state.machines[id] = nil
                state.remachine(from: base.name, to: nil)
                changes.append(.machineDeleted(base.name))
            case .mergeExercise(let base, let into, let moves):
                guard let sourceID = state.ownExercise(named: base.name), let source = state.exercises[sourceID] else {
                    // Merged already, a file taken twice — or deleted here
                    // with nothing logged, which comes to the same.
                    if !state.isInUse(base.name) { continue }
                    return .failure(Refused(conflict: .exerciseDeletedHere(base.name)))
                }
                guard source == base else { return .failure(Refused(conflict: .exerciseChangedHere(source.name))) }
                let targetID: UUID?
                let target: SyncExercise
                if let catalogKey = into.catalogKey {
                    guard let current = state.catalog[catalogKey] else {
                        return .failure(Refused(conflict: .exerciseDeletedHere(into.exercise.name)))
                    }
                    targetID = nil
                    target = current
                } else {
                    guard let id = state.ownExercise(named: into.exercise.name), let current = state.exercises[id] else {
                        return .failure(Refused(conflict: .exerciseDeletedHere(into.exercise.name)))
                    }
                    targetID = id
                    target = current
                }
                guard target == into.exercise else { return .failure(Refused(conflict: .exerciseChangedHere(target.name))) }
                let refused = Refused(conflict: .exerciseCannotMerge(base.name, into: target.name))
                let mapping = FieldMapping(moves)
                guard targetID != sourceID, source.tracksSets == target.tracksSets,
                      let sourceSides = ExerciseSides(rawValue: source.sides), let targetSides = ExerciseSides(rawValue: target.sides),
                      sourceSides.canMerge(into: targetSides),
                      into.catalogKey == nil || !mapping.destinations.values.contains(.newField),
                      case .success(let merge) = DefinitionMerge.merge(
                          source: source.record(), into: target.record(catalogKey: into.catalogKey), mapping: mapping
                      )
                else { return .failure(refused) }
                let merged = SyncExercise(merge.merged)
                state.exercises[sourceID] = nil
                if let targetID {
                    state.exercises[targetID] = merged
                    state.photoHandovers[sourceID] = targetID
                }
                state.moveEntries(
                    of: source.name, to: target.name, catalogKey: into.catalogKey, fields: merged.fields, keyRewrite: merge.keyRewrite
                )
                changes.append(.exerciseMerged(source.name, into: target.name))
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
        case .gymAdded(let name): "gym \(name) added"
        case .gymChanged(let name): "gym \(name) changed"
        case .gymDeleted(let name): "gym \(name) deleted"
        case .machineAdded(let name): "machine \(name) added"
        case .machineChanged(let name): "machine \(name) changed"
        case .machineDeleted(let name): "machine \(name) deleted"
        case .exerciseMerged(let name, let target): "exercise \(name) merged into \(target)"
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
        case .gymChangedHere(let name): "gym \(name) was changed on this iPhone in the meantime"
        case .gymDeletedHere(let name): "gym \(name) was deleted on this iPhone in the meantime"
        case .gymNameTaken(let name): "a gym named \(name) is here already"
        case .machineChangedHere(let name): "machine \(name) was changed on this iPhone in the meantime"
        case .machineDeletedHere(let name): "machine \(name) was deleted on this iPhone in the meantime"
        case .machineNameTaken(let name): "a machine named \(name) is here already"
        case .exerciseCannotMerge(let name, let target): "\(name) cannot be merged into \(target)"
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
