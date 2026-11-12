import Foundation

/// What a definition in the store looks like to `CatalogSync` — the parts that
/// decide whether it is, or may become, a catalog exercise.
nonisolated struct CatalogCandidate: Hashable {
    var id: UUID
    var name: String
    var catalogKey: String?
    var muscleGroupNames: [String]
    var secondaryMuscleGroupNames: [String] = []
    /// The category's plain name, "" for none.
    var category: String = ExerciseCategory.strength.name
    /// What it logs — Weight and Reps in sets unless said otherwise.
    var shape: ExerciseShape = CatalogExercise.plain.shape
    var sides: ExerciseSides
    var offersAssistance: Bool = false
    /// Any entry with a filled set or a note. Only asked of a definition the
    /// catalog lets go.
    var isUsed: Bool = true
}

/// Brings the store in line with the catalog, run at every launch.
///
/// Decides only; `CatalogSync+Store` applies it. The rules:
/// - A catalog exercise missing from the store is added, whatever the
///   user's own exercises are called: the catalog is always complete, and an
///   own exercise under a catalog name is the user's version of it, beside it.
/// - An own exercise with exactly a catalog exercise's name (by
///   `exerciseKey`, nothing fuzzier) becomes that catalog exercise when it
///   could not tell the difference: the catalog's category and fields (by
///   `ExerciseShape`), no muscles or the catalog's (see
///   `CatalogCandidate.isFiledLike`), and trained either way or the
///   catalog's way. Anything else
///   stays the user's, and the catalog exercise is added beside it.
/// - A catalog exercise takes the catalog's name, muscles — main and
///   secondary — sides, and whether it can be assisted.
/// - A definition whose key the catalog no longer has becomes the user's own,
///   as it is — if it was ever used. Never used, it goes: an own exercise
///   nobody asked for would only be one more to clear away.
extension CatalogCandidate {
    /// Filed as the catalog files it. With secondary muscles picked, both
    /// lists must agree. Without, the exercise was filed — or imported from
    /// the list builds up to 20 shipped — when every muscle was one kind:
    /// it is filed like the catalog when it names all the catalog's main
    /// muscles and nothing the catalog does not name at all. Bench Press as
    /// Chest and Triceps is the catalog's; Back Squat as Quads alone is not.
    func isFiledLike(_ exercise: CatalogExercise) -> Bool {
        let main = Set(exercise.muscleGroupNames)
        let named = main.union(exercise.secondaryMuscleGroupNames)
        let mine = Set(muscleGroupNames)
        guard secondaryMuscleGroupNames.isEmpty else {
            return mine == main && Set(secondaryMuscleGroupNames) == Set(exercise.secondaryMuscleGroupNames)
        }
        return mine.isSuperset(of: main) && mine.isSubset(of: named)
    }
}

nonisolated struct CatalogSync: Equatable {
    var inserts: [CatalogExercise] = []
    var adoptions: [UUID: CatalogExercise] = [:]
    var refreshes: [UUID: CatalogExercise] = [:]
    var releases: Set<UUID> = []
    var deletions: Set<UUID> = []

    var isEmpty: Bool {
        inserts.isEmpty && adoptions.isEmpty && refreshes.isEmpty && releases.isEmpty && deletions.isEmpty
    }

    static func plan(catalog: [CatalogExercise], store: [CatalogCandidate]) -> CatalogSync {
        var sync = CatalogSync()
        let byKey = Dictionary(catalog.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var placedKeys = Set<String>()

        for candidate in store {
            guard let key = candidate.catalogKey else { continue }
            if let exercise = byKey[key], !placedKeys.contains(key) {
                placedKeys.insert(key)
                if candidate.name != exercise.name || candidate.muscleGroupNames != exercise.muscleGroupNames
                    || candidate.secondaryMuscleGroupNames != exercise.secondaryMuscleGroupNames
                    || candidate.sides != exercise.sides
                    || candidate.offersAssistance != exercise.offersAssistance {
                    sync.refreshes[candidate.id] = exercise
                }
            } else {
                // Gone from the catalog, or a second definition claiming a key
                // the first already holds: either way it is no catalog
                // exercise any more.
                if candidate.isUsed {
                    sync.releases.insert(candidate.id)
                } else {
                    sync.deletions.insert(candidate.id)
                }
            }
        }

        let ownByName = Dictionary(
            store.filter { $0.catalogKey == nil }.map { ($0.name.exerciseKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for exercise in catalog where !placedKeys.contains(exercise.key) {
            placedKeys.insert(exercise.key)
            if let own = ownByName[exercise.name.exerciseKey],
               own.category.exerciseKey == exercise.categoryName.exerciseKey,
               own.shape == exercise.shape,
               own.sides.canMerge(into: exercise.sides),
               own.muscleGroupNames.isEmpty || own.isFiledLike(exercise) {
                sync.adoptions[own.id] = exercise
            } else {
                sync.inserts.append(exercise)
            }
        }
        return sync
    }
}
