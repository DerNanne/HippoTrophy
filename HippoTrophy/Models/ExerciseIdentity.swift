import Foundation

extension String {
    /// The one rule for whether two exercise names mean the same exercise:
    /// compared case-insensitively, whitespace trimmed. Everything that asks
    /// — the editor's duplicate check, the picker, history grouping, the
    /// backup import — asks this and nothing else.
    ///
    /// This is a rule in code rather than a `@Attribute(.unique)` on the
    /// store, deliberately: the store cannot express a case-insensitive
    /// constraint, and a unique constraint turns an insert into an upsert,
    /// which is not what any caller here means by "already exists".
    ///
    /// Pure string logic, so not tied to the main actor: the backup's
    /// nonisolated records compare by it too.
    nonisolated var exerciseKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}

/// Which exercise something means — the one answer every place that groups
/// or finds by exercise asks: history, "last time", the graphs, the import.
///
/// A catalog exercise is its key. Its name is what the catalog calls it today,
/// in this language, and may be different tomorrow or on another device. The
/// user's own exercise is its name, by `exerciseKey`.
nonisolated enum ExerciseIdentity: Hashable {
    case catalog(String)
    case own(String)

    init(name: String, catalogKey: String?) {
        self = catalogKey.map(ExerciseIdentity.catalog) ?? .own(name.exerciseKey)
    }
}

/// Where a name may repeat. One name is one exercise among the user's own and
/// among the catalog's, but an own exercise may carry a catalog exercise's
/// name — its own version of it — and the two live side by side, told apart
/// by `ExerciseIdentity`.
nonisolated enum ExerciseNaming {
    /// Whether an exercise of the user's own may take `name`: no other own
    /// exercise has it. A catalog exercise of the name does not stand in the
    /// way. `others` is every definition but the one being named.
    static func isFree(_ name: String, amongOwn others: [(name: String, catalogKey: String?)]) -> Bool {
        !others.contains { $0.catalogKey == nil && $0.name.exerciseKey == name.exerciseKey }
    }

    /// The catalog exercise a name would shadow, if it is a catalog exercise's.
    static func catalogExercise(named name: String, in catalog: [CatalogExercise] = Catalog.exercises) -> CatalogExercise? {
        catalog.first { $0.name.exerciseKey == name.exerciseKey }
    }

    /// Said under the name field while the typed name is a catalog exercise's.
    /// A hint, not a warning: it is allowed, and the user should know what it
    /// makes of the list.
    static let catalogNameHint = "A catalog exercise has this name. Yours is listed next to it, marked User defined. Use the catalog exercise unless you need other muscle groups or fields."

    /// An own exercise under a catalog exercise's name — what gets the
    /// "User defined" mark.
    static func isOwnVersionOfCatalog(name: String, catalogKey: String?, in catalog: [CatalogExercise] = Catalog.exercises) -> Bool {
        catalogKey == nil && catalogExercise(named: name, in: catalog) != nil
    }

    /// Finds the exercise a name or an identity means among `candidates`.
    /// The identity first; failing that the name, preferring the kind the
    /// asker is: an own entry finds the user's own exercise before the
    /// catalog's, an entry with a key the device does not know finds a
    /// catalog exercise before an own one. Files from before the catalog
    /// name only the exercise, so a name with no own exercise under it leads
    /// to the catalog's.
    /// - Returns: the index into `candidates`.
    static func match(
        identity: ExerciseIdentity,
        name: String,
        among candidates: [(identity: ExerciseIdentity, name: String)]
    ) -> Int? {
        if let exact = candidates.firstIndex(where: { $0.identity == identity }) { return exact }
        let key = name.exerciseKey
        let named = candidates.indices.filter { candidates[$0].name.exerciseKey == key }
        let isCatalog: (Int) -> Bool = { if case .catalog = candidates[$0].identity { true } else { false } }
        switch identity {
        case .own: return named.first(where: { !isCatalog($0) }) ?? named.first
        case .catalog: return named.first(where: isCatalog) ?? named.first
        }
    }
}
