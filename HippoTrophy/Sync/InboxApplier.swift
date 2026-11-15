import Foundation
import SwiftData

/// Brings the store's templates and workouts to a state the planner worked
/// out, or back to the one before for Undo. They are read the way a backup
/// reads them and written the way an import writes them, so one from Desk
/// lands exactly like one from a file: its exercises found by identity, its
/// gym and machines by name, its sets numbered per side.
@MainActor
enum InboxApplier {
    static func state(in context: ModelContext) throws -> InboxState {
        let templates = try context.fetch(FetchDescriptor(
            predicate: WorkoutSession.templates, sortBy: [SortDescriptor(\.templateOrder)]
        ))
        let workouts = try context.fetch(FetchDescriptor(predicate: WorkoutSession.trained))
        let own = try context.fetch(FetchDescriptor<ExerciseDefinition>()).filter { $0.catalogKey == nil }
        return InboxState(
            templates: templates.map { SyncTemplate(BackupExporter.templateRecord($0)).normalized },
            workouts: workouts.map { SyncWorkout(BackupExporter.record($0)).normalized },
            exercises: Dictionary(own.map { ($0.id, SyncExercise(BackupExporter.record($0))) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// Makes the store's templates and workouts `target`: those that differ
    /// from `current` are written anew, those gone are deleted, and every
    /// template gets its place. Not saved — the caller saves, or rolls back.
    static func make(_ target: InboxState, from current: InboxState, in context: ModelContext) throws {
        // The exercises first: a rename reaches the entries already here,
        // which then need no writing anew. What is left to do to templates
        // and workouts is measured from there.
        try makeExercises(target, from: current, in: context)
        let now = current.exercises == target.exercises ? current : try state(in: context)
        try makeWorkouts(target, from: now, in: context)
        try makeTemplates(target, from: now, in: context)
    }

    /// The own exercises as `target` has them: changed ones in place, their
    /// entries renamed with them; new ones made under the id the state gave
    /// them — the one they had, when Undo brings one back, so the entries
    /// logged with it are its own again; gone ones deleted, their entries
    /// keeping what was logged.
    private static func makeExercises(_ target: InboxState, from current: InboxState, in context: ModelContext) throws {
        guard target.exercises != current.exercises else { return }
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = try context.fetch(FetchDescriptor<ExerciseEntry>())

        for id in current.exercises.keys where target.exercises[id] == nil {
            if let definition = byID[id] { context.delete(definition) }
        }
        var nextIndex = (definitions.map(\.orderIndex).max() ?? -1) + 1
        for (id, exercise) in target.exercises where current.exercises[id] != exercise {
            let definition: ExerciseDefinition
            if let found = byID[id] {
                definition = found
            } else {
                definition = ExerciseDefinition(name: exercise.name, orderIndex: nextIndex)
                definition.id = id
                nextIndex += 1
                context.insert(definition)
            }
            write(exercise, onto: definition, in: context)
            for entry in entries where entry.definitionID == id && entry.name != exercise.name {
                entry.name = exercise.name
            }
        }
    }

    /// What an exercise is, written as the exercise editor writes it. Fields
    /// are replaced only when they differ: the planner lets that happen only
    /// while nothing is logged with the exercise.
    private static func write(_ exercise: SyncExercise, onto definition: ExerciseDefinition, in context: ModelContext) {
        definition.name = exercise.name
        definition.categoryName = ExerciseCategory.resolve(exercise.category)?.name ?? ""
        definition.muscleGroupNames = exercise.muscleGroupNames
        definition.secondaryMuscleGroupNames = exercise.secondaryMuscleGroupNames
        definition.tracksSets = exercise.tracksSets
        definition.sides = ExerciseSides(rawValue: exercise.sides) ?? .both
        definition.offersAssistance = exercise.offersAssistance
        definition.restSeconds = exercise.restSeconds
        let fields = definition.sortedFields.map { SyncField(key: $0.key, label: $0.label, type: $0.typeRawValue) }
        guard fields != exercise.fields else { return }
        for field in definition.fields {
            context.delete(field)
        }
        definition.fields = []
        for (index, field) in exercise.fields.enumerated() {
            let stored = FieldDefinition(key: field.key, label: field.label, typeRawValue: field.type, orderIndex: index, definition: definition)
            definition.fields.append(stored)
            context.insert(stored)
        }
    }

    private static func makeWorkouts(_ target: InboxState, from current: InboxState, in context: ModelContext) throws {
        let changed = target.workouts.values.filter { current.workouts[$0.id] != $0 }
        let gone = current.workouts.keys.filter { target.workouts[$0] == nil }
        guard !changed.isEmpty || !gone.isEmpty else { return }
        let sessions = try context.fetch(FetchDescriptor(predicate: WorkoutSession.trained))
        var byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in gone + changed.map(\.id) {
            if let session = byID.removeValue(forKey: id) {
                context.delete(session)
            }
        }
        guard !changed.isEmpty else { return }
        try importing(BackupFile(exportedAt: .now, workouts: changed.sorted { $0.date < $1.date }.map(\.record)),
                      selection: ImportSelection(exercises: false, workouts: true, templates: false), in: context)
    }

    /// Writes what a file holds the way an import does, without its questions:
    /// exercises are the ones here, nothing is asked.
    private static func importing(_ file: BackupFile, selection: ImportSelection, in context: ModelContext) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let plan = ImportPlanner.plan(
            file: file,
            existing: definitions.map { ImportPlanner.Existing(id: $0.id, record: BackupExporter.record($0)) },
            knownWorkoutIDs: [],
            knownTemplateIDs: []
        )
        _ = BackupImporter(context: context).apply(plan, decisions: ImportDecisions(), selection: selection)
    }

    private static func makeTemplates(_ target: InboxState, from current: InboxState, in context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor(predicate: WorkoutSession.templates))
        var byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let changed = target.templates.values.filter { current.templates[$0.id] != $0 }
        let gone = current.templates.keys.filter { target.templates[$0] == nil }
        for id in gone + changed.map(\.id) {
            if let session = byID.removeValue(forKey: id) {
                context.delete(session)
            }
        }

        if !changed.isEmpty {
            // What was here before the import, the sessions just deleted
            // among them: a fetch before saving may still hand those back, under
            // the very ids the new ones get.
            let before = Set(try context.fetch(FetchDescriptor(predicate: WorkoutSession.templates)).map(\.persistentModelID))
            try importing(BackupFile(exportedAt: .now, templates: changed.map(\.record)),
                          selection: ImportSelection(exercises: false, workouts: false, templates: true), in: context)
            for session in try context.fetch(FetchDescriptor(predicate: WorkoutSession.templates))
            where !before.contains(session.persistentModelID) {
                byID[session.id] = session
            }
        }

        // Every template's place from the target: the import put the new
        // ones first and moved the rest back, which the target says better.
        for (index, id) in target.order.enumerated() {
            byID[id]?.templateOrder = index
        }
    }
}
