import Foundation
import SwiftData

/// What a workout looked like when the editor opened, so Cancel can tell
/// whether anything changed and put it back if it did. Values rather than
/// model objects: the objects are what gets replaced. A gym and a machine are
/// held as they are — they are picked, never replaced.
@MainActor
struct WorkoutSnapshot: Equatable {
    let name: String
    let date: Date
    let notes: String
    let gym: Gym?
    let exercises: [ExerciseSnapshot]

    init(session: WorkoutSession) {
        name = session.name
        date = session.date
        notes = session.notes
        gym = session.gym
        exercises = session.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(ExerciseSnapshot.init)
    }

    func differs(from session: WorkoutSession, workoutName: String, notes: String) -> Bool {
        let current = WorkoutSnapshot(session: session)
        return current.date != date
            || current.gym?.id != gym?.id
            || current.exercises != exercises
            || workoutName != name
            || notes != self.notes
    }

    func restore(_ session: WorkoutSession, in modelContext: ModelContext) {
        for exercise in session.exercises {
            modelContext.delete(exercise)
        }
        session.exercises = []
        session.name = name
        session.date = date
        session.notes = notes
        session.gym = gym

        for snapshot in exercises {
            let exercise = snapshot.makeExercise(session: session, in: modelContext)
            session.exercises.append(exercise)
        }
    }
}

@MainActor
struct ExerciseSnapshot: Equatable {
    let id: UUID
    let name: String
    let notes: String
    let instructions: String
    let machine: Machine?
    let orderIndex: Int
    let tracksUnilateral: Bool
    let logsSidesSeparately: Bool
    let effortScale: EffortScale
    let definitionID: UUID
    let catalogKey: String?
    let assistance: Assistance
    let supersetID: UUID?
    let startSideRawValue: String?
    let sets: [SetSnapshot]

    init(_ exercise: ExerciseEntry) {
        id = exercise.id
        name = exercise.name
        notes = exercise.notes
        instructions = exercise.instructions
        machine = exercise.machine
        orderIndex = exercise.orderIndex
        tracksUnilateral = exercise.tracksUnilateral
        logsSidesSeparately = exercise.logsSidesSeparately
        effortScale = exercise.effortScale
        definitionID = exercise.definitionID
        catalogKey = exercise.catalogKey
        assistance = exercise.assistance
        supersetID = exercise.supersetID
        startSideRawValue = exercise.startSideRawValue
        sets = exercise.sets.sorted { $0.id.uuidString < $1.id.uuidString }.map(SetSnapshot.init)
    }

    func makeExercise(session: WorkoutSession, in modelContext: ModelContext) -> ExerciseEntry {
        let exercise = ExerciseEntry(
            name: name,
            notes: notes,
            instructions: instructions,
            orderIndex: orderIndex,
            definitionID: definitionID,
            supersetID: supersetID,
            tracksUnilateral: tracksUnilateral,
            logsSidesSeparately: logsSidesSeparately,
            effortScale: effortScale,
            catalogKey: catalogKey,
            assistance: assistance,
            session: session
        )
        exercise.machine = machine
        exercise.startSideRawValue = startSideRawValue
        exercise.id = id
        modelContext.insert(exercise)

        for snapshot in sets {
            let set = snapshot.makeSet(exercise: exercise, in: modelContext)
            exercise.sets.append(set)
        }
        return exercise
    }
}

@MainActor
struct SetSnapshot: Equatable {
    let id: UUID
    let setNumber: Int
    let sideRawValue: String
    let effortValue: Double?
    let supersetPosition: Int?
    let sideOrder: Int?
    let isDone: Bool
    let values: [FieldValueSnapshot]

    init(_ set: SetEntry) {
        id = set.id
        setNumber = set.setNumber
        sideRawValue = set.sideRawValue
        effortValue = set.effortValue
        supersetPosition = set.supersetPosition
        sideOrder = set.sideOrder
        isDone = set.isDone
        values = set.values.sorted { $0.id.uuidString < $1.id.uuidString }.map(FieldValueSnapshot.init)
    }

    func makeSet(exercise: ExerciseEntry, in modelContext: ModelContext) -> SetEntry {
        let set = SetEntry(
            setNumber: setNumber,
            sideRawValue: sideRawValue,
            effortValue: effortValue,
            supersetPosition: supersetPosition,
            sideOrder: sideOrder,
            isDone: isDone,
            exercise: exercise
        )
        set.id = id
        modelContext.insert(set)
        for snapshot in values {
            let value = snapshot.makeValue(set: set)
            set.values.append(value)
            modelContext.insert(value)
        }
        return set
    }
}

@MainActor
struct FieldValueSnapshot: Equatable {
    let id: UUID
    let fieldKey: String
    let label: String
    let typeRawValue: String
    let orderIndex: Int
    let textValue: String?
    let numberValue: Double?

    init(_ value: FieldValue) {
        id = value.id
        fieldKey = value.fieldKey
        label = value.label
        typeRawValue = value.typeRawValue
        orderIndex = value.orderIndex
        textValue = value.textValue
        numberValue = value.numberValue
    }

    func makeValue(set: SetEntry) -> FieldValue {
        let value = FieldValue(
            fieldKey: fieldKey,
            label: label,
            typeRawValue: typeRawValue,
            orderIndex: orderIndex,
            textValue: textValue,
            numberValue: numberValue,
            set: set
        )
        value.id = id
        return value
    }
}
