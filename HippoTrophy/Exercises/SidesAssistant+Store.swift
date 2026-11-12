import Foundation
import SwiftData

extension SidesAssistant {
    /// The own exercises still undecided, with what was logged under them.
    @MainActor
    static func load(in context: ModelContext) -> SidesAssistant {
        let undecided = undecidedDefinitions(in: context)
        let entries = ExerciseHistory.fetch(in: context).entries
        let byDefinition = Dictionary(grouping: entries, by: \.definitionID)
        let exercises = undecided.map { definition in
            Exercise(
                id: definition.id,
                name: definition.name,
                muscleGroupNames: definition.muscleGroupNames,
                entries: (byDefinition[definition.id] ?? [])
                    .sorted { ($0.session?.date ?? .distantPast) > ($1.session?.date ?? .distantPast) }
                    .map { entry in
                        Entry(
                            id: entry.id,
                            mode: entry.unilateralMode,
                            date: entry.session?.date ?? .distantPast,
                            workout: entry.session?.name ?? "",
                            sets: entry.sets.filter(\.hasLoggedData).count
                        )
                    }
            )
        }
        return SidesAssistant(exercises: exercises.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    /// Whether anything is left for the assistant — then nothing else may
    /// come first.
    @MainActor
    static func isNeeded(in context: ModelContext) -> Bool {
        !undecidedDefinitions(in: context).isEmpty
    }

    @MainActor
    private static func undecidedDefinitions(in context: ModelContext) -> [ExerciseDefinition] {
        ((try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []).filter { !$0.isCatalog && $0.sides == .either }
    }

    /// Writes every decided outcome: the exercise's side, the entries' modes,
    /// and the unilateral exercise a split hands its entries to — a copy of
    /// the exercise's shape under a name nobody holds yet.
    @MainActor
    func apply(in context: ModelContext) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = Dictionary(ExerciseHistory.fetch(in: context).entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var takenNames = Set(definitions.map(\.name.exerciseKey))
        var orderIndex = (definitions.map(\.orderIndex).max() ?? -1) + 1

        for exercise in exercises {
            guard let outcome = outcome(for: exercise), let definition = byID[exercise.id] else { continue }
            for id in outcome.deletions {
                guard let entry = entries[id] else { continue }
                // A superset of one is no superset: the partner left behind
                // is an exercise of its own again.
                if let supersetID = entry.supersetID {
                    let rest = entries.values.filter { $0.id != id && $0.supersetID == supersetID }
                    if rest.count == 1, let partner = rest.first {
                        SupersetPair.dissolve(partner)
                    }
                }
                context.delete(entry)
            }
            definition.sides = outcome.sides
            for (id, mode) in outcome.modes {
                entries[id]?.applyMode(mode)
            }
            guard !outcome.split.isEmpty else { continue }

            var name = SideMigration.ownVariantName(of: definition.name)
            var number = 2
            while takenNames.contains(name.exerciseKey) {
                name = "\(SideMigration.ownVariantName(of: definition.name)) \(number)"
                number += 1
            }
            takenNames.insert(name.exerciseKey)

            let unilateral = ExerciseDefinition(
                name: name,
                orderIndex: orderIndex,
                categoryName: definition.categoryName,
                muscleGroupNames: definition.muscleGroupNames,
                secondaryMuscleGroupNames: definition.secondaryMuscleGroupNames,
                tracksSets: definition.tracksSets,
                sides: .one
            )
            orderIndex += 1
            context.insert(unilateral)
            for field in definition.sortedFields {
                let copy = FieldDefinition(
                    key: field.key, label: field.label, typeRawValue: field.typeRawValue,
                    orderIndex: field.orderIndex, definition: unilateral
                )
                unilateral.fields.append(copy)
                context.insert(copy)
            }
            for id in outcome.split {
                guard let entry = entries[id] else { continue }
                entry.definitionID = unilateral.id
                entry.name = unilateral.name
                entry.catalogKey = nil
            }
        }
        try context.save()
    }
}
