import Foundation
import SwiftData

extension SidesSettlement {
    /// Applies the plan to the store, once: the first launch after the update
    /// marks itself done in `defaults`, and a store that comes later — an
    /// import — can only be in a format written after it. Run after
    /// `CatalogSync`, so an own exercise the catalog adopts counts as the
    /// catalog's.
    @MainActor
    static func runOnce(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: SettingsKey.sidesSettled) else { return }

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let entries = ExerciseHistory.fetch(in: context).entries
        let plan = plan(exercises(definitions, entries: entries))

        UnusedExercises.delete(plan.deletions, definitions: definitions, entries: entries, in: context)
        for definition in definitions {
            if plan.undecided.contains(definition.id) {
                definition.sides = .either
            } else if plan.bilateral.contains(definition.id) {
                definition.sides = .both
            }
        }
        try context.save()
        defaults.set(true, forKey: SettingsKey.sidesSettled)
    }

    /// Deletes every own exercise never used, once more: the first launch of
    /// build 22 marks itself done in `defaults`. What the settlement above
    /// left — an exercise decided since, or one that came after it — goes
    /// now; what is made from here on is wanted, and stays until its owner
    /// deletes it.
    @MainActor
    static func dropUnusedOnce(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: SettingsKey.unusedDropped) else { return }

        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let entries = ExerciseHistory.fetch(in: context).entries
        let unused = unused(exercises(definitions, entries: entries))
        UnusedExercises.delete(unused, definitions: definitions, entries: entries, in: context)
        try context.save()
        defaults.set(true, forKey: SettingsKey.unusedDropped)
    }

    /// Deletes the `leftovers`, with their empty entries. Run at every launch
    /// after `runOnce`, and after an import; cheap when there are none.
    @MainActor
    static func dropLeftovers(in context: ModelContext) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        guard definitions.contains(where: { !$0.isCatalog && $0.sides == .either }) else { return }
        let entries = ExerciseHistory.fetch(in: context).entries
        let leftovers = leftovers(exercises(definitions, entries: entries))
        guard !leftovers.isEmpty else { return }

        UnusedExercises.delete(leftovers, definitions: definitions, entries: entries, in: context)
        try context.save()
    }

    @MainActor
    private static func exercises(_ definitions: [ExerciseDefinition], entries: [ExerciseEntry]) -> [Exercise] {
        let used = UnusedExercises.used(in: entries)
        return definitions.map { definition in
            Exercise(
                id: definition.id,
                isCatalog: definition.isCatalog,
                tracksSets: definition.tracksSets,
                isCardio: definition.category == .cardio,
                isOneSided: definition.sides == .one,
                isUndecided: definition.sides == .either,
                isUsed: used.contains(definition.id)
            )
        }
    }
}
