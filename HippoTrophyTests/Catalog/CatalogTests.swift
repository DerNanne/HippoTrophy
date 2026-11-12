import Foundation
import Testing
@testable import HippoTrophy

/// The catalog loader drops a broken file without a word, and the store
/// believes whatever it reads, so the shipped file is held to its rules here.
struct CatalogTests {
    @Test func theShippedCatalogReads() {
        #expect(!Catalog.exercises.isEmpty)
    }

    @Test func keysAndNamesAreUnique() {
        let keys = Catalog.exercises.map(\.key)
        let names = Catalog.exercises.map(\.name.exerciseKey)
        #expect(Set(keys).count == keys.count)
        #expect(Set(names).count == names.count)
    }

    /// A key is forever, so it is kept boring: lowercase, digits, dashes.
    @Test func keysAreKebabCase() {
        for key in Catalog.exercises.map(\.key) {
            #expect(key.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil, "\(key)")
        }
    }

    /// The heat map is why the catalog exists; an exercise without muscles, or
    /// with one the app does not know, would quietly not count.
    @Test func everyExerciseTrainsKnownMuscles() {
        for exercise in Catalog.exercises {
            let main = MuscleGroup.read(exercise.muscleGroupNames)
            let secondary = MuscleGroup.read(exercise.secondaryMuscleGroupNames)
            #expect(!exercise.muscleGroupNames.isEmpty, "\(exercise.key)")
            #expect(main.unknown.isEmpty && main.muscles == exercise.muscleGroupNames, "\(exercise.key)")
            #expect(secondary.unknown.isEmpty && secondary.muscles == exercise.secondaryMuscleGroupNames, "\(exercise.key)")
        }
    }

    /// A muscle is main or secondary, not both.
    @Test func noMuscleIsMainAndSecondaryAtOnce() {
        for exercise in Catalog.exercises {
            #expect(Set(exercise.muscleGroupNames).isDisjoint(with: exercise.secondaryMuscleGroupNames), "\(exercise.key)")
        }
    }

    /// The one-sided form trains what the two-sided one does.
    @Test func aOneSidedFormTrainsWhatItsTwoSidedExerciseDoes() throws {
        for variant in Catalog.exercises {
            guard let key = variant.unilateralOf else { continue }
            let exercise = try #require(Catalog.exercise(forKey: key))
            #expect(variant.muscleGroupNames == exercise.muscleGroupNames, "\(variant.key)")
            #expect(variant.secondaryMuscleGroupNames == exercise.secondaryMuscleGroupNames, "\(variant.key)")
        }
    }

    @Test func pushUpsAreForTheChestWithShouldersAndTricepsHelping() throws {
        let pushUp = try #require(Catalog.exercise(forKey: "push-up"))
        #expect(pushUp.name == "Push-Up")
        #expect(pushUp.muscleGroupNames == ["chest"])
        #expect(Set(pushUp.secondaryMuscleGroupNames).isSuperset(of: ["shoulders", "triceps"]))
    }

    /// The case that brought secondary muscles in: a squat is for the legs,
    /// Quads and Glutes alike.
    @Test func squatsAreForQuadsAndGlutes() throws {
        let squat = try #require(Catalog.exercise(forKey: "back-squat"))
        #expect(squat.muscleGroupNames == ["quads", "glutes"])
        #expect(squat.secondaryMuscleGroupNames.contains("adductors"))
    }

    /// The one-sided form of a two-sided exercise is an exercise of its own,
    /// so the catalog has no exercise trained either way.
    @Test func everyCatalogExerciseIsTwoSidedOrOneSided() {
        #expect(!Catalog.exercises.contains { $0.sides == .either })
    }

    /// A one-sided form names its two-sided exercise, trains the same muscles
    /// and is called after it.
    @Test func everyOneSidedFormBelongsToATwoSidedExercise() throws {
        let variants = Catalog.exercises.filter { $0.unilateralOf != nil }
        #expect(!variants.isEmpty)
        for variant in variants {
            let base = try #require(Catalog.exercise(forKey: variant.unilateralOf ?? ""), "\(variant.key)")
            #expect(variant.sides == .one, "\(variant.key)")
            #expect(base.sides == .both, "\(variant.key)")
            #expect(base.unilateralOf == nil, "\(variant.key)")
            #expect(variant.muscleGroupNames == base.muscleGroupNames, "\(variant.key)")
            #expect(variant.name == SideMigration.ownVariantName(of: base.name), "\(variant.key)")
            #expect(variants.filter { $0.unilateralOf == base.key }.count == 1, "\(base.key)")
        }
    }

    @Test func legPressHasItsOneSidedForm() {
        #expect(Catalog.unilateralVariant(of: "leg-press")?.name == "Leg Press (Unilateral)")
        #expect(Catalog.exercise(forKey: "bulgarian-split-squat")?.sides == .one)
        #expect(Catalog.exercise(forKey: "glute-kickback-machine")?.sides == .one)
    }

    /// The other bars and handles of the cable are exercises of their own until
    /// there is a grip field. They train what the plain one does, and none has
    /// a one-sided form: a neutral or close grip is held with both hands.
    @Test func theGripVariantsTrainWhatTheirPlainExerciseDoesAndStayTwoSided() throws {
        let plain = ["lat-pulldown": "Lat Pulldown", "seated-cable-row": "Seated Cable Row"]
        for (key, name) in plain {
            let base = try #require(Catalog.exercise(forKey: key))
            for grip in ["Neutral Grip", "Close Grip"] {
                let variant = try #require(Catalog.exercise(forKey: "\(key)-\(grip.lowercased().replacingOccurrences(of: " ", with: "-"))"))
                #expect(variant.name == "\(name) (\(grip))")
                #expect(variant.muscleGroupNames == base.muscleGroupNames, "\(variant.key)")
                #expect(variant.secondaryMuscleGroupNames == base.secondaryMuscleGroupNames, "\(variant.key)")
                #expect(variant.sides == .both, "\(variant.key)")
                #expect(Catalog.unilateralVariant(of: variant.key) == nil, "\(variant.key)")
            }
        }
    }

    /// The lunge on the Smith machine is trained one side at a time and has no
    /// two-sided form, like the lunge it is drawn after.
    @Test func theSmithMachineLungeIsOneSidedAndTrainsWhatTheLungeDoes() throws {
        let lunge = try #require(Catalog.exercise(forKey: "lunge"))
        let smith = try #require(Catalog.exercise(forKey: "smith-machine-lunge"))
        #expect(smith.name == "Smith Machine Lunge")
        #expect(smith.sides == .one)
        #expect(smith.unilateralOf == nil)
        #expect(smith.muscleGroupNames == lunge.muscleGroupNames)
        #expect(smith.secondaryMuscleGroupNames == lunge.secondaryMuscleGroupNames)
    }

    /// The skull crusher of before named no tool, so nobody can tell whether an
    /// EZ bar or dumbbells were logged under it. Its key is retired, like the
    /// overhead extension's, and never given out again.
    @Test func theSkullCrusherWithoutAToolIsRetired() throws {
        #expect(Catalog.exercise(forKey: "skull-crusher") == nil)
        let tools = ["ez-bar", "dumbbell"].map { Catalog.exercise(forKey: "\($0)-skull-crusher") }
        #expect(tools.map { $0?.name } == ["EZ Bar Skull Crusher", "Dumbbell Skull Crusher"])
        for tool in tools {
            let skullCrusher = try #require(tool)
            #expect(skullCrusher.muscleGroupNames == ["triceps"], "\(skullCrusher.key)")
            #expect(skullCrusher.sides == .both, "\(skullCrusher.key)")
        }
    }

    /// The ab wheel rollout left the catalog before the first release. Its key
    /// is retired: whoever logged it keeps it as an exercise of their own.
    @Test func theAbWheelRolloutIsRetired() {
        #expect(Catalog.exercise(forKey: "ab-wheel-rollout") == nil)
        #expect(!Catalog.exercises.contains { $0.name == "Ab Wheel Rollout" })
    }

    /// Shrugs are why Traps is a group of its own rather than part of Back.
    @Test func shrugsTrainTheTraps() throws {
        let shrug = try #require(Catalog.exercise(forKey: "dumbbell-shrug"))
        #expect(shrug.muscleGroupNames == ["traps"])
    }

    /// The overhead extension of before named no tool, so nobody can tell
    /// whether a dumbbell, a cable or a machine was logged under it. Its key is
    /// retired: a store that has it lets it go to My Exercises, where Review My
    /// Exercises offers the three that say. A retired key is never given out
    /// again — a store or a backup may still carry it.
    @Test func theOverheadExtensionWithoutAToolIsRetired() {
        #expect(Catalog.exercise(forKey: "overhead-triceps-extension") == nil)
        let tools = ["dumbbell", "cable", "machine"].map { Catalog.exercise(forKey: "\($0)-overhead-triceps-extension")?.name }
        #expect(tools == [
            "Dumbbell Overhead Triceps Extension",
            "Cable Overhead Triceps Extension",
            "Machine Overhead Triceps Extension"
        ])
    }

    /// What a catalog exercise logs is set once, when it is added, so the
    /// file has to get it right: a category the app ships, fields of a kind
    /// it knows under keys of their own, the standard ones under theirs.
    @MainActor
    @Test func everyExerciseLogsWhatTheAppKnows() {
        for exercise in Catalog.exercises {
            #expect(ExerciseCategory.resolve(exercise.categoryName) != nil, "\(exercise.key)")
            let fields = exercise.fieldRecords
            #expect(!fields.isEmpty, "\(exercise.key)")
            #expect(Set(fields.map(\.key)).count == fields.count, "\(exercise.key)")
            #expect(Set(fields.map(\.label.exerciseKey)).count == fields.count, "\(exercise.key)")
            for field in fields {
                let type = FieldType(rawValue: field.type)
                #expect(type != nil && type != .assistance, "\(exercise.key): \(field.label)")
                if let type, type.isStandard {
                    #expect(field.key == type.standardKey && field.label == type.displayName, "\(exercise.key): \(field.label)")
                } else {
                    #expect(field.key.wholeMatch(of: /f[0-9]+/) != nil, "\(exercise.key): \(field.key)")
                }
            }
        }
    }

    /// Mostly done one leg at a time, after an injury; held, so under
    /// Isometrics, with how long and at which knee angle.
    @Test func theIsometricLegExtensionIsOneSidedAndHeld() throws {
        let hold = try #require(Catalog.exercise(forKey: "isometric-leg-extension"))
        #expect(hold.name == "Isometric Leg Extension")
        #expect(hold.sides == .one)
        #expect(hold.unilateralOf == nil)
        #expect(hold.categoryName == ExerciseCategory.isometrics.name)
        #expect(hold.logsSets)
        #expect(hold.fieldRecords.map(\.label) == ["Weight", "Hold", "Knee Angle"])
        #expect(hold.fieldRecords.map(\.type) == ["weight", "time", "number"])
        #expect(hold.muscleGroupNames == ["quads"])
    }

    /// The warm-up most people in a gym do: once per workout, under Cardio,
    /// with what the machine shows. Speed is distance over time, so the
    /// treadmill asks for the incline instead.
    @Test func theBikeAndTheTreadmillAreLoggedOncePerWorkout() throws {
        let bike = try #require(Catalog.exercise(forKey: "exercise-bike"))
        let treadmill = try #require(Catalog.exercise(forKey: "treadmill"))
        for exercise in [bike, treadmill] {
            #expect(exercise.categoryName == ExerciseCategory.cardio.name, "\(exercise.key)")
            #expect(!exercise.logsSets, "\(exercise.key)")
            #expect(exercise.sides == .both, "\(exercise.key)")
            #expect(exercise.fieldRecords.first?.type == "time", "\(exercise.key)")
            #expect(exercise.fieldRecords.map(\.label).contains("Distance (km)"), "\(exercise.key)")
            #expect(exercise.fieldRecords.map(\.label).contains("Heart Rate"), "\(exercise.key)")
        }
        #expect(bike.name == "Exercise Bike")
        #expect(bike.fieldRecords.map(\.label) == ["Duration", "Distance (km)", "Level", "Heart Rate"])
        #expect(treadmill.fieldRecords.map(\.label) == ["Duration", "Distance (km)", "Incline (%)", "Heart Rate"])
    }
}
