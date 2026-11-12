import Foundation
import SwiftData

extension CatalogSync {
    /// Plans against what the store holds and applies it, then moves the
    /// entries that no longer fit how their exercise is trained — see
    /// `SideMigration`. Called at launch and after an import; cheap when
    /// nothing changed, which is every launch but the first after an update.
    ///
    /// An own exercise made for such a move counts as kept in the review of
    /// My Exercises: it is the one-sided form the catalog does not have yet,
    /// and there is nothing to decide about it. `defaults` is where the review
    /// keeps that list.
    @MainActor
    static func run(
        catalog: [CatalogExercise] = Catalog.exercises,
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))
        let entries = ExerciseHistory.fetch(in: context).entries
        let used = UnusedExercises.used(in: entries)
        let sync = plan(
            catalog: catalog,
            store: definitions.map {
                CatalogCandidate(
                    id: $0.id,
                    name: $0.name,
                    catalogKey: $0.catalogKey,
                    muscleGroupNames: $0.muscleGroupNames,
                    secondaryMuscleGroupNames: $0.secondaryMuscleGroupNames,
                    category: $0.categoryName,
                    shape: BackupExporter.record($0).shape,
                    sides: $0.sides,
                    offersAssistance: $0.offersAssistance,
                    isUsed: used.contains($0.id)
                )
            }
        )
        for definition in definitions {
            if let exercise = sync.adoptions[definition.id] ?? sync.refreshes[definition.id] {
                definition.catalogKey = exercise.key
                definition.name = exercise.name
                definition.muscleGroupNames = exercise.muscleGroupNames
                definition.secondaryMuscleGroupNames = exercise.secondaryMuscleGroupNames
                definition.sides = exercise.sides
                definition.offersAssistance = exercise.offersAssistance
            } else if sync.releases.contains(definition.id) {
                definition.catalogKey = nil
            }
        }
        if !sync.deletions.isEmpty {
            UnusedExercises.delete(sync.deletions, definitions: definitions, entries: entries, in: context)
            // What follows fetches again, and must not find them.
            try context.save()
        }
        var orderIndex = (definitions.map(\.orderIndex).max() ?? -1) + 1
        for exercise in sync.inserts {
            let definition = ExerciseDefinition.insert(exercise, orderIndex: orderIndex, in: context)
            definition.secondaryMuscleGroupNames = exercise.secondaryMuscleGroupNames
            definition.sides = exercise.sides
            definition.offersAssistance = exercise.offersAssistance
            orderIndex += 1
        }

        let current = try context.fetch(FetchDescriptor<ExerciseDefinition>(sortBy: [SortDescriptor(\.orderIndex)]))
        let sidesMoved = moveEntriesToTheirSides(current, catalog: catalog, in: context, defaults: defaults)
        let all = sidesMoved ? try context.fetch(FetchDescriptor<ExerciseDefinition>()) : current
        let entriesMoved = pullEntriesAlong(all, in: context)
        if !sync.isEmpty || sidesMoved || entriesMoved {
            try context.save()
        }
    }

    /// Applies `SideMigration` to every entry of a catalog exercise.
    /// - Returns: whether anything changed.
    @MainActor
    private static func moveEntriesToTheirSides(
        _ definitions: [ExerciseDefinition],
        catalog: [CatalogExercise],
        in context: ModelContext,
        defaults: UserDefaults
    ) -> Bool {
        let byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(
            definitions.compactMap { definition in definition.catalogKey.map { ($0, definition) } },
            uniquingKeysWith: { first, _ in first }
        )
        var ownByName = Dictionary(
            definitions.filter { !$0.isCatalog }.map { ($0.name.exerciseKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var orderIndex = (definitions.map(\.orderIndex).max() ?? -1) + 1
        var kept = KeptOwnExercises(stored: defaults.string(forKey: SettingsKey.keptOwnExercises) ?? "")
        var changed = false

        func ownExercise(named name: String, muscleGroupNames: [String], secondary: [String]) -> ExerciseDefinition? {
            if let own = ownByName[name.exerciseKey] {
                // Weight and Reps or nothing: the entry's values are those.
                return own.isPlainSetsAndReps ? own : nil
            }
            let made = ExerciseDefinition.insertPlainSetsAndReps(
                name: name, orderIndex: orderIndex, muscleGroupNames: muscleGroupNames, in: context
            )
            made.secondaryMuscleGroupNames = secondary
            made.sides = .one
            orderIndex += 1
            ownByName[name.exerciseKey] = made
            kept.ids.insert(made.id)
            return made
        }

        for entry in ExerciseHistory.fetch(in: context).entries {
            guard let definition = byID[entry.definitionID], definition.tracksSets,
                  let move = SideMigration.move(mode: entry.unilateralMode, exerciseKey: definition.catalogKey, catalog: catalog)
            else { continue }
            let target: ExerciseDefinition?
            switch move {
            case .mode(let mode):
                entry.applyMode(mode)
                changed = true
                continue
            case .catalog(let key):
                target = byKey[key]
            case .own(let name, let muscleGroupNames, let secondary):
                target = ownExercise(named: name, muscleGroupNames: muscleGroupNames, secondary: secondary)
            }
            guard let target else { continue }
            entry.definitionID = target.id
            entry.catalogKey = target.catalogKey
            entry.name = target.name
            changed = true
        }

        if changed {
            defaults.set(kept.stored, forKey: SettingsKey.keptOwnExercises)
        }
        return changed
    }

    /// Every entry carries what its definition is: a catalog exercise's key
    /// and name, or no key for an own one. Catches up on what the plan above
    /// just changed, and on entries logged before entries carried a key at
    /// all (`SchemaV2`). Entries whose definition is gone keep what they have.
    /// - Returns: whether anything changed.
    @MainActor
    private static func pullEntriesAlong(_ definitions: [ExerciseDefinition], in context: ModelContext) -> Bool {
        let byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for entry in ExerciseHistory.fetch(in: context).entries {
            guard let definition = byID[entry.definitionID] else { continue }
            if entry.catalogKey != definition.catalogKey {
                entry.catalogKey = definition.catalogKey
                changed = true
            }
            // An own exercise's entries keep the name they were logged under
            // until the user renames it; a catalog exercise's follow the
            // catalog, which renames without asking.
            if definition.isCatalog, entry.name != definition.name {
                entry.name = definition.name
                changed = true
            }
        }
        return changed
    }
}
