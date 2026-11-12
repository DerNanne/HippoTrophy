import Foundation

/// What `ExerciseFilter` needs to know of an exercise. The store's definitions
/// have it; tests use plain values.
protocol ExerciseFilterable {
    var name: String { get }
    var muscleGroups: [MuscleGroup] { get }
    var categoryName: String { get }
    var isCatalog: Bool { get }
}

extension ExerciseDefinition: ExerciseFilterable {}

/// One choice in the muscle menu. An exercise counts under its main muscle
/// groups; the ones filed under none are a choice of their own, so they can be
/// found and filed.
enum MuscleFilter: Hashable {
    case muscle(MuscleGroup)
    case unfiled

    var name: String {
        switch self {
        case .muscle(let muscle): return muscle.displayName
        case .unfiled: return "No Muscle Group"
        }
    }

    private static let unfiledStored = "none"

    /// `nil` for what no choice was stored as, and for a muscle no longer there.
    init?(stored: String) {
        if stored == Self.unfiledStored {
            self = .unfiled
        } else if let muscle = MuscleGroup(rawValue: stored) {
            self = .muscle(muscle)
        } else {
            return nil
        }
    }

    var stored: String {
        switch self {
        case .muscle(let muscle): return muscle.rawValue
        case .unfiled: return Self.unfiledStored
        }
    }

    func includes(_ muscles: [MuscleGroup]) -> Bool {
        switch self {
        case .muscle(let muscle): return muscles.contains(muscle)
        case .unfiled: return muscles.isEmpty
        }
    }
}

/// What the exercise list is narrowed to: a search, a category, a muscle and
/// the user's own exercises, all at once. Whatever is left is in alphabetical order: an exercise added or
/// imported lands where it will be looked for.
struct ExerciseFilter: Equatable {
    var query = ""
    /// A `CategoryFilter.id(of:)` value; `nil` is every category.
    var categoryID: String?
    var muscle: MuscleFilter?
    var onlyOwn = false

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNarrowed: Bool {
        !trimmedQuery.isEmpty || categoryID != nil || muscle != nil || onlyOwn
    }

    func apply<Exercise: ExerciseFilterable>(to exercises: [Exercise]) -> [Exercise] {
        let query = trimmedQuery
        return exercises
            .filter { exercise in
                (query.isEmpty || exercise.name.localizedCaseInsensitiveContains(query))
                    && (categoryID == nil || Self.categoryID(of: exercise.categoryName) == categoryID)
                    && (muscle?.includes(exercise.muscleGroups) ?? true)
                    && (!onlyOwn || !exercise.isCatalog)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether the own exercises are worth a button: with none of them it could
    /// only lead to nothing, unless it is on, so it can be turned off again.
    func offersOnlyOwn<Exercise: ExerciseFilterable>(among exercises: [Exercise]) -> Bool {
        onlyOwn || exercises.contains { !$0.isCatalog }
    }

    /// The categories worth a chip: those an exercise is in, of the own ones
    /// while only those are shown, plus the one picked, so a choice does not
    /// vanish from under the finger. A chip that can only lead to nothing would
    /// be noise.
    func categoryOptions<Exercise: ExerciseFilterable>(among exercises: [Exercise]) -> [CategoryFilter.Option] {
        let used = Set(exercises.filter { !onlyOwn || !$0.isCatalog }.map { Self.categoryID(of: $0.categoryName) })
        return CategoryFilter.options.filter { option in
            let id = CategoryFilter.id(of: option)
            return used.contains(id) || id == categoryID
        }
    }

    /// The search as the name of a new exercise, unless an exercise of that
    /// name exists — whatever the filter hides, because one name is one exercise.
    func newName<Exercise: ExerciseFilterable>(among exercises: [Exercise]) -> String? {
        let name = trimmedQuery
        guard !name.isEmpty, !exercises.contains(where: { $0.name.exerciseKey == name.exerciseKey }) else { return nil }
        return name
    }

    private static func categoryID(of categoryName: String) -> String {
        CategoryFilter.id(of: ExerciseCategory.resolve(categoryName))
    }
}
