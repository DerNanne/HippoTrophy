import Foundation
import SwiftData

/// Brings the store's templates to a state the planner worked out, or back
/// to the one before for Undo. Templates are read the way a backup reads
/// them and written the way an import writes them, so a template from Desk
/// lands exactly like one from a file: its exercises found by identity, its
/// gym and machines by name, its sets numbered per side.
@MainActor
enum InboxApplier {
    static func state(in context: ModelContext) throws -> TemplateState {
        let templates = try context.fetch(FetchDescriptor(
            predicate: WorkoutSession.templates, sortBy: [SortDescriptor(\.templateOrder)]
        ))
        return TemplateState(templates: templates.map { SyncTemplate(BackupExporter.templateRecord($0)).normalized })
    }

    /// Makes the store's templates `target`: those that differ from `current`
    /// are written anew, those gone are deleted, and every one gets its
    /// place. Not saved — the caller saves, or rolls back.
    static func make(_ target: TemplateState, from current: TemplateState, in context: ModelContext) throws {
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
            let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
            let file = BackupFile(exportedAt: .now, templates: changed.map(\.record))
            let plan = ImportPlanner.plan(
                file: file,
                existing: definitions.map { ImportPlanner.Existing(id: $0.id, record: BackupExporter.record($0)) },
                knownWorkoutIDs: [],
                knownTemplateIDs: []
            )
            _ = BackupImporter(context: context).apply(
                plan, decisions: ImportDecisions(),
                selection: ImportSelection(exercises: false, workouts: false, templates: true)
            )
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
