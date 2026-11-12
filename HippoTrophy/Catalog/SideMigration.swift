import Foundation

/// Where an entry goes whose mode no longer fits how its catalog exercise is
/// trained — decided here, applied by `CatalogSync` at every launch and after
/// an import.
///
/// Before the catalog said how an exercise is trained, every catalog exercise
/// offered every mode, so Leg Press holds entries logged left and right, and
/// Bulgarian Split Squat entries logged "normal" because that was where a new
/// entry started. Each is moved to where it belongs, without asking:
/// - A two-sided exercise's one-sided entry goes to its one-sided form in the
///   catalog, keeping its mode.
/// - Where the catalog has no one-sided form yet, it goes to the user's own
///   exercise "<name> (Unilateral)", made for it if need be. When the
///   catalog gains that form under that name, `CatalogSync` adopts the own
///   exercise, entries and all.
/// - A one-sided exercise's two-sided entry stays, logged one-sided with the
///   same weight: one side was trained either way, and the numbers are what
///   one side moved.
///
/// Only catalog exercises are touched: an own exercise's entries are as the
/// user logged them. New entries cannot land here again — a two-sided
/// exercise offers no one-sided mode and a one-sided one no two-sided — so
/// running it again finds nothing.
nonisolated enum SideMigration {
    enum Move: Equatable {
        /// To the catalog exercise under this key.
        case catalog(key: String)
        /// To the user's own exercise of this name, one-sided, with these
        /// muscles if it has to be made.
        case own(name: String, muscleGroupNames: [String], secondaryMuscleGroupNames: [String] = [])
        /// Stays where it is, switched to this mode.
        case mode(UnilateralMode)
    }

    /// The move for an entry logged in `mode` from the catalog exercise under
    /// `exerciseKey`, or nil when it is where it belongs.
    static func move(mode: UnilateralMode, exerciseKey: String?, catalog: [CatalogExercise]) -> Move? {
        guard let key = exerciseKey, let exercise = catalog.first(where: { $0.key == key }) else { return nil }
        switch exercise.sides {
        case .one:
            return mode == .bilateral ? .mode(.oneSided) : nil
        case .both:
            guard mode != .bilateral else { return nil }
            if let variant = Catalog.unilateralVariant(of: key, in: catalog) {
                return .catalog(key: variant.key)
            }
            return .own(
                name: ownVariantName(of: exercise.name),
                muscleGroupNames: exercise.muscleGroupNames,
                secondaryMuscleGroupNames: exercise.secondaryMuscleGroupNames
            )
        case .either:
            return nil
        }
    }

    /// The name the catalog would give the one-sided form, so the own
    /// exercise is adopted by name the day the catalog has it.
    static func ownVariantName(of name: String) -> String {
        "\(name) (Unilateral)"
    }
}
