import Foundation
import SwiftData

/// Writes a merge into the store: the carried-over fields onto the target,
/// and the entries that were logged from the source onto the target. The
/// decision of *what* moves where was made by `DefinitionMerge`; this only
/// carries it out.
@MainActor
enum ExerciseMerging {
    /// Appends the fields the merge carried over to the target definition.
    static func addCarriedFields(_ result: DefinitionMerge.Result, to target: ExerciseDefinition, in context: ModelContext) {
        let known = Set(target.fields.map(\.key))
        var nextIndex = target.fields.count
        for record in result.merged.fields where !known.contains(record.key) {
            let field = FieldDefinition(
                key: record.key,
                label: record.label,
                typeRawValue: record.type,
                orderIndex: nextIndex,
                definition: target
            )
            target.fields.append(field)
            context.insert(field)
            nextIndex += 1
        }
    }

    /// Hangs one entry on a definition: the link, the name, and in every set
    /// the values' keys rewritten by the merge plus an empty value for every
    /// field of the definition the set does not have yet. Values under keys
    /// the definition does not know are left alone — nothing here drops data.
    static func attach(_ entry: ExerciseEntry, to definition: ExerciseDefinition, keyRewrite: [String: String], in context: ModelContext) {
        entry.definitionID = definition.id
        entry.name = definition.name
        entry.catalogKey = definition.catalogKey
        for set in entry.sets {
            align(set, to: definition, keyRewrite: keyRewrite, in: context)
        }
    }

    /// One set's values lined up with the definition's fields — the same rule
    /// the exercise editor applies after a field change. A field is logged
    /// the way the entry's help says: the weight of an assisted entry stays
    /// the help.
    static func align(_ set: SetEntry, to definition: ExerciseDefinition, keyRewrite: [String: String], in context: ModelContext) {
        for value in set.values {
            if let newKey = keyRewrite[value.fieldKey] {
                value.fieldKey = newKey
            }
        }
        let assistance = set.exercise?.assistance ?? .unassisted
        for (index, field) in definition.sortedFields.enumerated() {
            let type = assistance.loggedType(for: field.type)
            let label = assistance.loggedLabel(for: field.type, label: field.label)
            if let value = set.values.first(where: { $0.fieldKey == field.key }) {
                value.label = label
                value.orderIndex = index
                if value.type != type {
                    value.convert(to: type)
                }
            } else {
                let value = FieldValue(
                    fieldKey: field.key,
                    label: label,
                    typeRawValue: type.rawValue,
                    orderIndex: index,
                    set: set
                )
                set.values.append(value)
                context.insert(value)
            }
        }
    }

    /// Folds one stored exercise into another: fields carried over, every
    /// entry logged from the source moved to the target, the source deleted.
    /// The caller saves.
    static func merge(
        _ source: ExerciseDefinition,
        into target: ExerciseDefinition,
        mapping: FieldMapping,
        in context: ModelContext
    ) throws {
        let result = try DefinitionMerge.merge(
            source: BackupExporter.record(source),
            into: BackupExporter.record(target),
            mapping: mapping
        ).get()
        addCarriedFields(result, to: target, in: context)

        for entry in ExerciseHistory.fetch(in: context).entries(loggedFrom: source.id) {
            attach(entry, to: target, keyRewrite: result.keyRewrite, in: context)
        }
        // The target keeps its own picture; only one without takes the source's.
        if target.photo == nil, !target.isCatalog, let photo = source.ownPhoto {
            source.photo = nil
            target.photo = photo
        }
        context.delete(source)
    }

    /// How many workouts a merge would move, for saying so before it happens.
    static func workoutCount(loggedFrom definition: ExerciseDefinition, in context: ModelContext) -> Int {
        ExerciseHistory.fetch(in: context).entries(loggedFrom: definition.id).trainedWorkoutCount
    }
}
