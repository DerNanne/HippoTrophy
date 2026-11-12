import Foundation
import Testing
@testable import HippoTrophy

/// The planner decides what an import does without touching a store. These
/// pin the rule it rests on: two exercises are the same when their name, kind
/// and fields are — nothing else counts, and nothing else is silently changed.
struct ImportPlannerTests {
    private func exercise(
        _ name: String,
        category: String = "Strength",
        muscles: [String] = [],
        tracksSets: Bool = true,
        fields: [(String, String)] = []
    ) -> ExerciseRecord {
        ExerciseRecord(
            name: name, category: category, muscleGroupNames: muscles, tracksSets: tracksSets,
            sides: tracksSets ? "either" : "both",
            fields: fields.enumerated().map { FieldRecord(key: "f\($0.offset + 1)", label: $0.element.0, type: $0.element.1) }
        )
    }

    private func existing(_ record: ExerciseRecord) -> ImportPlanner.Existing {
        ImportPlanner.Existing(id: UUID(), record: record)
    }

    private func plan(file: [ExerciseRecord], existing: [ExerciseRecord], workouts: [WorkoutRecord] = [], known: Set<UUID> = []) -> ImportPlan {
        ImportPlanner.plan(
            file: BackupFile(exportedAt: .now, exercises: file, workouts: workouts),
            existing: existing.map(self.existing),
            knownWorkoutIDs: known
        )
    }

    /// Every app brings the catalog, so the import sheet counts only the
    /// user's own exercises, each name once, as the planner reads them.
    @Test func theFileCountsOnlyOwnExercises() {
        var bench = exercise("Barbell Bench Press")
        bench.catalogKey = "barbell-bench-press"
        let file = BackupFile(exportedAt: .now, exercises: [bench, exercise("Rowing"), exercise(" rowing "), exercise("Sled Push")])
        #expect(file.ownExerciseCount == 2)
        #expect(!file.bringsNothing)
    }

    /// A file of catalog exercises and nothing else has nothing to bring.
    @Test func catalogExercisesAloneBringNothing() {
        var bench = exercise("Barbell Bench Press")
        bench.catalogKey = "barbell-bench-press"
        #expect(BackupFile(exportedAt: .now, exercises: [bench]).bringsNothing)
        #expect(!BackupFile(exportedAt: .now, exercises: [bench], workouts: [WorkoutRecord(id: UUID(), name: "", date: .now, notes: "", exercises: [])]).bringsNothing)
    }

    /// The review shows what sets a catalog conflict apart when the fields
    /// are the same, so the planner's reasons are readable from outside.
    @Test func theDifferencesBehindACatalogConflictCanBeRead() {
        var catalog = exercise("Barbell Bench Press", muscles: ["chest", "triceps"], fields: [("Weight", "weight"), ("Reps", "reps")])
        catalog.catalogKey = "barbell-bench-press"
        let theirs = exercise("Barbell Bench Press", muscles: ["chest"], fields: [("Weight", "weight"), ("Reps", "reps")])
        #expect(ImportPlanner.differences(between: catalog, and: theirs) == [
            .muscles(local: catalog.muscleFiling, file: theirs.muscleFiling)
        ])
    }

    @Test func anUnknownNameIsAdded() {
        let plan = plan(file: [exercise("Squat")], existing: [])
        guard case .add = plan.exercises.first?.outcome else { Issue.record("expected add"); return }
        #expect(!plan.needsReview)
    }

    /// Case and surrounding whitespace are not a different exercise.
    @Test func theSameExerciseIsRecognisedRegardlessOfCase() {
        let plan = plan(file: [exercise(" bench PRESS ")], existing: [exercise("Bench Press")])
        guard case .same = plan.exercises.first?.outcome else { Issue.record("expected same"); return }
    }

    /// Two devices that made the same exercise made it with their own keys and
    /// in their own order. Neither is a difference in what the exercise is.
    @Test func fieldOrderAndKeysDoNotMakeADifferentExercise() {
        let mine = ExerciseRecord(name: "Rowing", category: "Cardio", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
            FieldRecord(key: "f1", label: "Time", type: "time"), FieldRecord(key: "f2", label: "Distance", type: "number")
        ])
        let theirs = ExerciseRecord(name: "Rowing", category: "Cardio", muscleGroupNames: [], tracksSets: false, sides: "both", fields: [
            FieldRecord(key: "f9", label: "distance", type: "number"), FieldRecord(key: "f3", label: "Time", type: "time")
        ])
        let plan = plan(file: [theirs], existing: [mine])
        guard case .review(_, let differences) = plan.exercises.first?.outcome else { Issue.record("expected review"); return }
        #expect(differences == [.fieldOrder(local: ["Time", "Distance"], file: ["distance", "Time"])])
    }

    @Test func categoryAndMusclesAreQuestionsNotIdentity() {
        let plan = plan(
            file: [exercise("Deadlift", category: "Mobility", muscles: ["back", "glutes"])],
            existing: [exercise("Deadlift", category: "Strength", muscles: ["back"])]
        )
        guard case .review(_, let differences) = plan.exercises.first?.outcome else { Issue.record("expected review"); return }
        #expect(differences.count == 2)
        #expect(plan.needsReview)
    }

    /// A different field, or a different kind, is another exercise wearing the
    /// same name — and that is the user's call.
    @Test func aDifferentShapeUnderTheSameNameIsAConflict() {
        let plan = plan(
            file: [exercise("Rowing", tracksSets: false, fields: [("Time", "time"), ("Heart Rate", "number")])],
            existing: [exercise("Rowing", tracksSets: false, fields: [("Time", "time")])]
        )
        guard case .conflict = plan.exercises.first?.outcome else { Issue.record("expected conflict"); return }

        let kind = self.plan(file: [exercise("Plank", tracksSets: false, fields: [("Time", "time")])],
                             existing: [exercise("Plank", tracksSets: true, fields: [("Time", "time")])])
        guard case .conflict = kind.exercises.first?.outcome else { Issue.record("expected conflict"); return }
    }

    /// A file that names one exercise twice means one exercise.
    @Test func aDuplicateInTheFileIsPlannedOnce() {
        let plan = plan(file: [exercise("Squat"), exercise("squat")], existing: [])
        #expect(plan.exercises.count == 1)
    }

    @Test func aKnownWorkoutIsSkippedAndAnUnknownOneAdded() {
        let known = UUID()
        let workouts = [
            WorkoutRecord(id: known, name: "", date: .now, notes: "", exercises: []),
            WorkoutRecord(id: UUID(), name: "", date: .now, notes: "", exercises: [])
        ]
        let plan = plan(file: [], existing: [], workouts: workouts, known: [known])
        #expect(plan.workouts.map(\.isKnown) == [true, false])
    }

    /// Whether an exercise offers the one-sided modes is an attribute two
    /// devices can disagree on, not a different exercise.
    @Test func sidesAreAQuestionNotIdentity() {
        var theirs = exercise("Plank", tracksSets: true, fields: [("Hold", "time")])
        theirs.sides = "both"
        let mine = exercise("Plank", tracksSets: true, fields: [("Hold", "time")])
        let plan = plan(file: [theirs], existing: [mine])

        guard case .review(_, let differences) = plan.exercises.first?.outcome else { Issue.record("expected review"); return }
        #expect(differences == [.sides(local: .either, file: .both)])
    }

    /// How a catalog exercise is trained is the catalog's: a file that says
    /// otherwise — one from before format 11 cannot know — asks nothing.
    @Test func aCatalogExercisesSidesAreNotAQuestion() {
        var theirs = exercise("Leg Press", tracksSets: true, fields: [("Weight", "weight"), ("Reps", "reps")])
        theirs.catalogKey = "leg-press"
        theirs.sides = "either"
        var mine = theirs
        mine.sides = "both"
        let plan = plan(file: [theirs], existing: [mine])
        guard case .same = plan.exercises.first?.outcome else { Issue.record("expected same"); return }
    }

    @Test func decisionsDefaultToMine() {
        let decisions = ImportDecisions()
        #expect(decisions.side(for: "Deadlift", .category(local: "a", file: "b")) == .mine)
        #expect(decisions.resolution(for: "Deadlift") == nil)
    }

    /// The testers' case: a format-8 file names an exercise the device now
    /// has as a catalog exercise. Own on one side, catalog on the other, but
    /// the same sets and fields — the same exercise, nothing to ask.
    @Test func anOwnExerciseInTheFileIsTheCatalogExerciseOfItsName() {
        var catalog = exercise("Back Squat", muscles: ["quads", "glutes"], fields: [("Weight", "weight"), ("Reps", "reps")])
        catalog.catalogKey = "back-squat"
        let plan = plan(file: [exercise("back squat", fields: [("Weight", "weight"), ("Reps", "reps")])], existing: [catalog])
        guard case .same = plan.exercises.first?.outcome else { Issue.record("expected same"); return }
        #expect(!plan.needsReview)
    }

    /// No muscles in the file is "not filed yet", not a choice to weigh
    /// against the device's.
    @Test func noMusclesInTheFileIsNoQuestion() {
        let plan = plan(file: [exercise("Squat")], existing: [exercise("Squat", muscles: ["quads"])])
        guard case .same = plan.exercises.first?.outcome else { Issue.record("expected same"); return }
    }

    /// A catalog exercise is found by its key even under another name — the
    /// catalog in another language.
    @Test func aCatalogExerciseIsMatchedByKeyNotName() {
        var here = exercise("Barbell Bench Press", fields: [("Weight", "weight"), ("Reps", "reps")])
        here.catalogKey = "barbell-bench-press"
        var there = exercise("Bankdrücken (Langhantel)", fields: [("Weight", "weight"), ("Reps", "reps")])
        there.catalogKey = "barbell-bench-press"
        let plan = plan(file: [there], existing: [here])
        guard case .same = plan.exercises.first?.outcome else { Issue.record("expected same"); return }
    }

    /// The file cannot change a catalog exercise's details: different ones
    /// ask whether to leave it to the catalog or bring the file's in as an
    /// exercise of the user's own.
    @Test func aCatalogExerciseWithOtherDetailsIsAQuestionOfWhose() {
        var catalog = exercise("Barbell Bench Press", muscles: ["chest", "triceps"], fields: [("Weight", "weight"), ("Reps", "reps")])
        catalog.catalogKey = "barbell-bench-press"
        let plan = plan(file: [exercise("Barbell Bench Press", muscles: ["chest", "shoulders"], fields: [("Weight", "weight"), ("Reps", "reps")])], existing: [catalog])
        guard case .conflict = plan.exercises.first?.outcome else { Issue.record("expected conflict"); return }
        #expect(plan.needsReview)
    }

    /// Whether an own exercise can be assisted is a question like its sides;
    /// a catalog exercise's is the catalog's.
    @Test func whetherAnOwnExerciseCanBeAssistedIsAskedACatalogOnesIsNot() {
        var mine = exercise("Pull-Up", fields: [("Weight", "weight"), ("Reps", "reps")])
        var theirs = mine
        theirs.offersAssistance = true
        guard case .review(_, let differences) = plan(file: [theirs], existing: [mine]).exercises.first?.outcome else {
            Issue.record("expected review"); return
        }
        #expect(differences == [.assistance(local: false, file: true)])

        mine.catalogKey = "pull-up"
        theirs.catalogKey = "pull-up"
        guard case .same = plan(file: [theirs], existing: [mine]).exercises.first?.outcome else {
            Issue.record("expected same"); return
        }
    }
}
