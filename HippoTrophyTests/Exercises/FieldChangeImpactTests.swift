import Foundation
import Testing
@testable import HippoTrophy

/// What the exercise editor warns about before Save: which field changes reach
/// into logged values, and which of them lose something.
@MainActor
struct FieldChangeImpactTests {
    private let workoutA = UUID()
    private let workoutB = UUID()

    private func stored(_ key: String, _ label: String, _ type: FieldType, now: FieldType? = nil, removed: Bool = false) -> FieldDraft {
        FieldDraft(key: key, label: label, type: now ?? type, storedID: UUID(), originalType: type, isRemoved: removed)
    }

    private func value(_ key: String, _ type: FieldType, text: String? = nil, number: Double? = nil, in workout: UUID) -> FieldChangeImpact.LoggedValue {
        .init(fieldKey: key, label: key.capitalized, type: type, textValue: text, numberValue: number, workoutID: workout)
    }

    @Test func anUnchangedFieldCostsNothing() {
        var field = stored("f2", "Distance", .number)
        field.label = "Distance (km)"
        let impact = FieldChangeImpact(
            fields: [field],
            loggedValues: [value("f2", .number, number: 5, in: workoutA)],
            loggedWorkoutCount: 1
        )
        #expect(impact.isEmpty)
        #expect(!impact.losesData)
    }

    @Test func removingAFieldWithValuesLosesThemAndCountsWorkouts() throws {
        let field = stored("f2", "Distance", .number, removed: true)
        let impact = FieldChangeImpact(
            fields: [field],
            loggedValues: [
                value("f2", .number, number: 5, in: workoutA),
                value("f2", .number, number: 6, in: workoutA),
                value("f2", .number, number: 7, in: workoutB),
                value("f2", .number, in: workoutB),
            ],
            loggedWorkoutCount: 2
        )
        let line = try #require(impact.line(for: field))
        #expect(line.text == "Will be deleted, and with it 3 logged values in 2 workouts.")
        #expect(line.isDestructive)
        #expect(impact.losesData)
        #expect(impact.lines.count == 1)
    }

    @Test func removingAFieldNothingLoggedLosesNothing() throws {
        let field = stored("f2", "Distance", .number, removed: true)
        let impact = FieldChangeImpact(fields: [field], loggedValues: [value("f2", .number, in: workoutA)], loggedWorkoutCount: 1)
        let line = try #require(impact.line(for: field))
        #expect(line.text == "Will be deleted. Nothing logged it yet.")
        #expect(!impact.losesData)
    }

    @Test func aNewFieldIsAddedEmptyToEveryLoggedWorkout() throws {
        var field = FieldDraft(key: "f3")
        field.label = "Incline"
        let impact = FieldChangeImpact(fields: [field], loggedValues: [], loggedWorkoutCount: 2)
        let line = try #require(impact.line(for: field))
        #expect(line.label == "Incline")
        #expect(line.text == "New. Added empty to 2 logged workouts — nothing was measured there.")
        #expect(!line.isDestructive)
    }

    @Test func aNewFieldOnAnUntrainedExerciseIsJustNew() throws {
        let field = FieldDraft(key: "f3")
        let impact = FieldChangeImpact(fields: [field], loggedValues: [], loggedWorkoutCount: 0)
        let line = try #require(impact.line(for: field))
        #expect(line.label == "Untitled field")
        #expect(line.text == "New field.")
    }

    @Test func aTypeChangeThatReadsEveryValueLosesNothing() throws {
        let field = stored("f2", "Distance", .number, now: .text)
        let impact = FieldChangeImpact(
            fields: [field],
            loggedValues: [value("f2", .number, number: 5, in: workoutA), value("f2", .number, number: 2.5, in: workoutB)],
            loggedWorkoutCount: 2
        )
        let line = try #require(impact.line(for: field))
        #expect(line.text == "Number → Text. 2 logged values converted.")
        #expect(!impact.losesData)
    }

    @Test func aTypeChangeThatCannotReadAValueSaysHowMany() throws {
        let field = stored("f2", "Pace", .text, now: .number)
        let impact = FieldChangeImpact(
            fields: [field],
            loggedValues: [
                value("f2", .text, text: "12", in: workoutA),
                value("f2", .text, text: "easy", in: workoutB),
            ],
            loggedWorkoutCount: 2
        )
        let line = try #require(impact.line(for: field))
        #expect(line.text == "Text → Number. 2 logged values converted, 1 of them cannot be read and will be cleared.")
        #expect(line.isDestructive)
    }

    @Test func valuesUnderAKeyNoFieldCoversAreDeletedOnce() {
        let kept = stored("reps", "Reps", .reps)
        let impact = FieldChangeImpact(
            fields: [kept],
            loggedValues: [
                value("reps", .reps, number: 8, in: workoutA),
                value("f9", .number, number: 1, in: workoutA),
                value("f9", .number, number: 2, in: workoutB),
            ],
            loggedWorkoutCount: 2
        )
        #expect(impact.lines.count == 1)
        #expect(impact.lines.first?.fieldID == nil)
        #expect(impact.lines.first?.label == "F9")
        #expect(impact.lines.first?.text == "Logged in your history but not a field of this exercise any more. Saving deletes 2 logged values in 2 workouts.")
        #expect(impact.losesData)
    }

    @Test func aFieldMarkedForRemovalIsNotCountedAgainAsALeftover() {
        let removed = stored("f9", "Distance", .number, removed: true)
        let impact = FieldChangeImpact(
            fields: [removed],
            loggedValues: [value("f9", .number, number: 1, in: workoutA)],
            loggedWorkoutCount: 1
        )
        #expect(impact.lines.map(\.fieldID) == [removed.id])
    }

    @Test func turningTrackSetsOffSaysWhatSplitsLastAndLosesNothing() {
        let impact = FieldChangeImpact(fields: [], loggedValues: [], loggedWorkoutCount: 3, splitWorkoutCount: 1)
        #expect(impact.lines.map(\.label) == ["No sets"])
        #expect(impact.message == "No sets: 1 workout holds several sets of this exercise. Each set becomes an entry of its own, in the same order.")
        #expect(!impact.losesData)
        #expect(FieldChangeImpact.splitText(workouts: 0) == nil)
    }
}
