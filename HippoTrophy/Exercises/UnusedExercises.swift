import Foundation
import SwiftData

/// An exercise never used — no entry with a filled set, none with a note —
/// can go without anything lost. Which ones go is decided elsewhere
/// (`SidesSettlement`, `CatalogSync`); this tells used from unused and
/// deletes, the same way for both.
enum UnusedExercises {
    /// The definitions with at least one entry that `belongsInHistory`.
    @MainActor
    static func used(in entries: [ExerciseEntry]) -> Set<UUID> {
        Set(entries.filter(\.belongsInHistory).map(\.definitionID))
    }

    /// Deletes the definitions and every entry of theirs — empty ones, if the
    /// decision was right.
    @MainActor
    static func delete(
        _ ids: Set<UUID>, definitions: [ExerciseDefinition], entries: [ExerciseEntry], in context: ModelContext
    ) {
        for entry in entries where ids.contains(entry.definitionID) {
            // A superset of one is no superset: the partner left behind is an
            // exercise of its own again.
            if let supersetID = entry.supersetID {
                let rest = entries.filter { $0.id != entry.id && $0.supersetID == supersetID && !ids.contains($0.definitionID) }
                if rest.count == 1, let partner = rest.first {
                    SupersetPair.dissolve(partner)
                }
            }
            context.delete(entry)
        }
        for definition in definitions where ids.contains(definition.id) {
            context.delete(definition)
        }
    }
}
