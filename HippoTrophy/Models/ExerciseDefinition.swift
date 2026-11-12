import Foundation
import SwiftData

/// One exercise the user can add to a workout: what the picker lists, what the
/// settings screen manages, and what an `ExerciseEntry` is logged from.
///
/// There is one kind of exercise. A set of it is a row of its fields: a plain
/// one has the two standard fields, Weight and Reps; any exercise can have up
/// to `maxFields` fields, standard ones included, and log them as sets or —
/// with `tracksSets` off — exactly once per workout.
@Model
final class ExerciseDefinition {
    /// Three fields fit a row in the workout editor, so six keeps an exercise at
    /// two tidy rows.
    static let maxFields = 6

    var id: UUID
    var name: String
    var orderIndex: Int
    /// The category's plain name, "" for none — see `ExerciseCategory`.
    var categoryName: String
    /// The muscles this exercise mainly trains, as raw values in the order
    /// they were picked; a set counts in full for each. Empty means "not filed
    /// yet" — every real exercise trains something, so there is no second,
    /// emptier state worth an `Optional`.
    var muscleGroupNames: [String]
    /// The muscles it trains along the way, a set counting half for each —
    /// see `MuscleGroupHistory`. Never one of `muscleGroupNames`. Added in
    /// `SchemaV5`, empty for everything before: what was picked then counted
    /// in full, as a main muscle does.
    var secondaryMuscleGroupNames: [String] = []
    /// Whether adding this exercise to a workout logs sets of reps and weight.
    /// Per-set effort comes with the sets.
    var tracksSets: Bool
    /// Half of `sides`, stored as it was before there were three: whether
    /// the one-sided modes are on offer at all. Never written directly.
    var allowsSides: Bool
    /// The other half of `sides`: with `allowsSides`, whether they are all
    /// there is. Added in `SchemaV4`; false for everything before, so an
    /// exercise that offered them is undecided until `SidesAssistant` asks.
    /// Never written directly.
    var onlyOneSided: Bool = false
    /// Whether its entries can be logged assisted — the help of a dip or
    /// pull-up machine in place of the weight; see `Assistance`. Only for an
    /// exercise with a weight field, which the help stands in for. Added in
    /// `SchemaV6`, false for everything before.
    var offersAssistance: Bool = false
    /// The catalog exercise this is, by its key in `Catalog.json`; nil for
    /// the user's own. A catalog exercise is the catalog's: its name, muscles,
    /// category and fields follow the catalog on every launch, and the editor
    /// offers a copy instead of changes. See `CatalogSync`.
    var catalogKey: String?
    /// How long to rest after a set of it, in seconds: nil follows the
    /// setting, 0 is no rest timer at all. The user's, catalog exercise or
    /// not — `CatalogSync` leaves it alone. Added in `SchemaV9`, nil for
    /// everything before.
    var restSeconds: Int?
    @Relationship(deleteRule: .cascade, inverse: \FieldDefinition.definition)
    var fields: [FieldDefinition]
    /// The picture the user gave it; read through `ownPhoto`. Added in
    /// `SchemaV16`, nil for everything before.
    @Relationship(deleteRule: .cascade, inverse: \ExercisePhoto.definition)
    var photo: ExercisePhoto?

    init(
        name: String,
        orderIndex: Int,
        categoryName: String = ExerciseCategory.strength.name,
        muscleGroupNames: [String] = [],
        secondaryMuscleGroupNames: [String] = [],
        tracksSets: Bool = true,
        sides: ExerciseSides = .both,
        offersAssistance: Bool = false,
        catalogKey: String? = nil,
        restSeconds: Int? = nil,
        fields: [FieldDefinition] = []
    ) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.categoryName = categoryName
        self.muscleGroupNames = muscleGroupNames
        self.secondaryMuscleGroupNames = secondaryMuscleGroupNames
        self.tracksSets = tracksSets
        self.allowsSides = sides != .both
        self.onlyOneSided = sides == .one
        self.offersAssistance = offersAssistance
        self.catalogKey = catalogKey
        self.restSeconds = restSeconds
        self.fields = fields
    }

    var isCatalog: Bool { catalogKey != nil }

    /// How this exercise is trained — which modes its entries offer. A new
    /// exercise is bilateral; a catalog exercise's follows the catalog.
    var sides: ExerciseSides {
        get {
            guard allowsSides else { return .both }
            return onlyOneSided ? .one : .either
        }
        set {
            allowsSides = newValue != .both
            onlyOneSided = newValue == .one
        }
    }

    var identity: ExerciseIdentity {
        ExerciseIdentity(name: name, catalogKey: catalogKey)
    }

    var category: ExerciseCategory? {
        ExerciseCategory.resolve(categoryName)
    }

    /// The main muscles, resolved to the fixed set, dropping anything
    /// unknown. Order is kept.
    var muscleGroups: [MuscleGroup] {
        muscleGroupNames.compactMap(MuscleGroup.from(raw:))
    }

    /// The muscles trained along the way, resolved the same way; one that is
    /// also a main muscle is a main muscle only.
    var secondaryMuscleGroups: [MuscleGroup] {
        let main = Set(muscleGroups)
        return secondaryMuscleGroupNames.compactMap(MuscleGroup.from(raw:)).filter { !main.contains($0) }
    }

    /// Both, main first: what an exercise trains and how much a set of it
    /// counts for each.
    var muscleTargets: MuscleTargets {
        MuscleTargets(primary: muscleGroups, secondary: secondaryMuscleGroups)
    }

    var sortedFields: [FieldDefinition] {
        fields.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Weight training, plain: sets of Weight and Reps, filed under Strength
    /// — what "an exercise" meant before fields existed. The editor shows such
    /// an exercise without the choices that are settled by being plain, so
    /// everything it leaves out has to be part of this. How it is trained is
    /// not: a bilateral and a unilateral exercise are both plain, and the
    /// editor shows that choice either way, and so is whether it can be
    /// assisted.
    var isPlainSetsAndReps: Bool {
        tracksSets
            && category == .strength
            && fields.count == 2
            && Set(fields.map(\.type)) == Set(FieldType.standard)
    }

    /// The one-line summary the picker and the settings list show under the
    /// name: what gets logged. Nothing for the plain case.
    var fieldSummary: String? {
        guard !isPlainSetsAndReps else { return nil }
        let labels = sortedFields.map(\.label).filter { !$0.isEmpty }
        let fields = labels.isEmpty ? "No fields" : labels.joined(separator: ", ")
        return tracksSets ? "Sets of \(fields)" : "Once per workout · \(fields)"
    }

    /// Inserts a plain sets-and-reps exercise, the way one is made from a
    /// typed name: the two standard fields and nothing else.
    @discardableResult
    static func insertPlainSetsAndReps(
        name: String,
        orderIndex: Int,
        muscleGroupNames: [String] = [],
        in context: ModelContext
    ) -> ExerciseDefinition {
        let definition = ExerciseDefinition(name: name, orderIndex: orderIndex, muscleGroupNames: muscleGroupNames)
        context.insert(definition)
        for (index, type) in FieldType.standard.enumerated() {
            let field = FieldDefinition(
                key: type.standardKey ?? type.rawValue,
                label: type.displayName,
                typeRawValue: type.rawValue,
                orderIndex: index,
                definition: definition
            )
            definition.fields.append(field)
            context.insert(field)
        }
        return definition
    }

    /// Inserts a catalog exercise as the catalog has it: its category, its
    /// fields under their keys, sets or once per workout. Name, muscles and
    /// sides are `CatalogSync`'s to keep in line.
    @discardableResult
    static func insert(_ exercise: CatalogExercise, orderIndex: Int, in context: ModelContext) -> ExerciseDefinition {
        let definition = ExerciseDefinition(
            name: exercise.name,
            orderIndex: orderIndex,
            categoryName: exercise.categoryName,
            muscleGroupNames: exercise.muscleGroupNames,
            tracksSets: exercise.logsSets,
            catalogKey: exercise.key
        )
        context.insert(definition)
        for (index, record) in exercise.fieldRecords.enumerated() {
            let field = FieldDefinition(key: record.key, label: record.label, typeRawValue: record.type, orderIndex: index, definition: definition)
            definition.fields.append(field)
            context.insert(field)
        }
        return definition
    }
}
