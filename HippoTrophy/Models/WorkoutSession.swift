import Foundation
import SwiftData

/// A workout, or a template to start one from.
///
/// A template is a workout that never happened: the same exercises, sets and
/// values, kept as a starting point. It is a session of its own rather than a
/// type of its own so the editor, the copy and everything that follows an
/// exercise's renames and merges reach it unchanged — and so everything that
/// asks what was *trained* has to leave it out. That question has one answer,
/// `isTemplate`, read through `WorkoutSession.trained` and
/// `ExerciseEntry.isInTemplate`.
@Model
final class WorkoutSession {
    var id: UUID
    var name: String
    /// When it was trained. A template's is when it was made, and means
    /// nothing.
    var date: Date
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.session)
    var exercises: [ExerciseEntry]
    /// Added in `SchemaV7`, false for everything before: there were no
    /// templates.
    var isTemplate: Bool = false
    /// Whether a template is put away: kept, but off the start screen. Read
    /// only on a template.
    var isArchived: Bool = false
    /// Where a template stands among the others on the start screen. Read
    /// only on a template.
    var templateOrder: Int = 0
    /// How long it took, from the editor's start to Finish, in whole
    /// seconds. Nil for a workout not timed: logged afterwards, from before
    /// there was a clock, or a template. Added in `SchemaV10`.
    var durationSeconds: Int?
    /// The day a template was adjusted for, at its start: set on a day
    /// variant — a copy of a template, changed for one workout and gone once
    /// it is trained — and nil on a template kept for good. Read only on a
    /// template. Added in `SchemaV11`.
    var plannedFor: Date?
    /// Where it was trained; nil where it was not said. On a template, where
    /// a workout started from it is trained. Added in `SchemaV13`.
    var gym: Gym?

    init(name: String = "", date: Date = .now, notes: String = "", exercises: [ExerciseEntry] = []) {
        self.id = UUID()
        self.name = name
        self.date = date
        self.notes = notes
        self.exercises = exercises
    }

    /// Every workout that was trained — what history, the activity graph and
    /// a backup's workouts are made of.
    static var trained: Predicate<WorkoutSession> {
        #Predicate { !$0.isTemplate }
    }

    /// Every template, archived ones included.
    static var templates: Predicate<WorkoutSession> {
        #Predicate { $0.isTemplate }
    }

    /// How many sets were done: every set with something logged in it, so the
    /// one row of an exercise logged once per workout counts as one and an
    /// empty set counts as none. This is the only count of sets — the list,
    /// the workout's page, "This Week" and the activity grid all read it, so a
    /// day in the grid is always the sum of that day's workouts.
    var setCount: Int {
        exercises.reduce(0) { $0 + $1.setCount }
    }

    /// How many exercises were trained: those with a set that counts. One
    /// holding only a note, or only empty sets, stays on the workout's page —
    /// it was on the plan — but was not trained.
    var exerciseCount: Int {
        exercises.filter(\.hasLoggedData).count
    }

    /// The sets not ticked off — planned, not done — in the order of the
    /// workout: what a new workout's first save asks about.
    var plannedSets: [SetEntry] {
        exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .flatMap(\.sortedSets)
            .filter { !$0.isDone }
    }

    /// Whether there is anything to start a template from: an exercise with
    /// a value in a set — done or planned, a plan is what a template is — or
    /// with instructions. A note does not count: it stays with its workout,
    /// so a workout of blank exercises and notes would give an empty card.
    /// What the history's menu asks before it offers one.
    var canBeKeptAsTemplate: Bool {
        exercises.contains {
            $0.sets.contains(where: \.hasValues)
                || !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The line under a workout, in the list and on its own page:
    /// `3 exercises • 12 sets`.
    var summary: String {
        let exerciseText = CountFormat.text(exerciseCount, "exercise", "exercises")
        let setText = CountFormat.text(setCount, "set", "sets")
        return "\(exerciseText) • \(setText)"
    }

    /// A new workout on `date` with this one's exercises, sets, values,
    /// instructions, gym and machines, as a starting point to train again. Each exercise's note
    /// stays behind: it says what happened in this workout, and the copy has
    /// yet to happen. A superset stays paired, under an id
    /// of its own so the copy and the original never share one. Not inserted:
    /// the caller inserts the session, which brings everything with it.
    func copy(dated date: Date) -> WorkoutSession {
        let copy = WorkoutSession(name: name, date: date, notes: notes)
        copy.gym = gym
        var supersetIDs: [UUID: UUID] = [:]

        for exercise in exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            var supersetID: UUID?
            if let old = exercise.supersetID {
                supersetID = supersetIDs[old] ?? UUID()
                supersetIDs[old] = supersetID
            }
            let copiedExercise = ExerciseEntry(
                name: exercise.name,
                instructions: exercise.instructions,
                orderIndex: exercise.orderIndex,
                definitionID: exercise.definitionID,
                supersetID: supersetID,
                tracksUnilateral: exercise.tracksUnilateral,
                logsSidesSeparately: exercise.logsSidesSeparately,
                effortScale: exercise.effortScale,
                catalogKey: exercise.catalogKey,
                assistance: exercise.assistance,
                session: copy
            )
            copiedExercise.machine = exercise.machine
            copiedExercise.startSideRawValue = exercise.startSideRawValue

            // Copied sets keep their values as a starting point, the way a
            // copied set inside the editor does — planned, not done: nothing
            // of the copy was trained yet.
            for set in exercise.sortedSets {
                let copiedSet = SetEntry(
                    setNumber: set.setNumber,
                    sideRawValue: set.sideRawValue,
                    effortValue: set.effortValue,
                    supersetPosition: set.supersetPosition,
                    sideOrder: set.sideOrder,
                    isDone: false,
                    exercise: copiedExercise
                )
                for value in set.sortedValues {
                    copiedSet.values.append(FieldValue(
                        fieldKey: value.fieldKey,
                        label: value.label,
                        typeRawValue: value.typeRawValue,
                        orderIndex: value.orderIndex,
                        textValue: value.textValue,
                        numberValue: value.numberValue,
                        set: copiedSet
                    ))
                }
                copiedExercise.sets.append(copiedSet)
            }

            copy.exercises.append(copiedExercise)
        }
        return copy
    }
}
