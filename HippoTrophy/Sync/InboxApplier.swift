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
        return InboxState(
            templates: templates.map { SyncTemplate(BackupExporter.templateRecord($0)).normalized },
            workouts: workouts.map { SyncWorkout(BackupExporter.record($0)).normalized }
        )
    }

    /// Makes the store's templates and workouts `target`: those that differ
    /// from `current` are written anew, those gone are deleted, and every
    /// template gets its place. Not saved — the caller saves, or rolls back.
    static func make(_ target: InboxState, from current: InboxState, in context: ModelContext) throws {
        try makeWorkouts(target, from: current, in: context)
        try makeTemplates(target, from: current, in: context)
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
