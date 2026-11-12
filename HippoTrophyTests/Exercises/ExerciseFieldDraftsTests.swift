import Foundation
import Testing
@testable import HippoTrophy

@MainActor
struct ExerciseFieldDraftsTests {
    private func plain() -> ExerciseFieldDrafts {
        ExerciseFieldDrafts(FieldType.standard.map(FieldDraft.init(standard:)), keysInUse: [])
    }

    private func stored(_ type: FieldType, key: String) -> FieldDraft {
        FieldDraft(key: key, label: type.displayName, type: type, storedID: UUID(), originalType: type)
    }

    private func types(_ drafts: [FieldDraft]) -> [FieldType] {
        drafts.map(\.type)
    }

    // MARK: What it opens as

    @Test func weightAndRepsInSetsOpensAsWeightAndRepsWhateverElseItLogs() {
        #expect(ExerciseLogKind.of(fieldTypes: [.weight, .reps], tracksSets: true) == .weightAndReps)
        #expect(ExerciseLogKind.of(fieldTypes: [.reps, .time, .weight], tracksSets: true) == .weightAndReps)
    }

    @Test func anythingElseOpensAsCustom() {
        #expect(ExerciseLogKind.of(fieldTypes: [.reps], tracksSets: true) == .custom)
        #expect(ExerciseLogKind.of(fieldTypes: [.number, .time], tracksSets: true) == .custom)
        #expect(ExerciseLogKind.of(fieldTypes: [.weight, .reps], tracksSets: false) == .custom)
        #expect(ExerciseLogKind.of(fieldTypes: [], tracksSets: true) == .custom)
    }

    // MARK: Switching

    @Test func customStartsEmptyOnANewExerciseAndBackBringsWeightAndReps() {
        var drafts = plain()
        drafts.becomeCustom()
        #expect(drafts.all.isEmpty)
        drafts.becomeWeightAndReps()
        #expect(types(drafts.activeInSetOrder) == [.weight, .reps])
    }

    @Test func ownFieldsSurviveBothWays() {
        var drafts = plain()
        drafts.add(.time)
        drafts.becomeCustom()
        #expect(types(drafts.active) == [.time])
        drafts.becomeWeightAndReps()
        #expect(types(drafts.activeInSetOrder) == [.weight, .reps, .time])
    }

    @Test func storedWeightAndRepsStayUnderCustom() {
        var drafts = ExerciseFieldDrafts([stored(.weight, key: "weight"), stored(.reps, key: "reps")], keysInUse: ["weight", "reps"])
        drafts.becomeCustom()
        #expect(types(drafts.active) == [.weight, .reps])
    }

    @Test func weightAndRepsPutsBackAStoredOneMarkedForDeletion() {
        let weight = stored(.weight, key: "weight")
        var drafts = ExerciseFieldDrafts([weight, stored(.reps, key: "reps")], keysInUse: ["weight", "reps"])
        drafts.remove(weight.id)
        #expect(types(drafts.active) == [.reps])

        drafts.becomeWeightAndReps()
        #expect(types(drafts.activeInSetOrder) == [.weight, .reps])
        #expect(drafts.all.count == 2)
        #expect(drafts.all.first { $0.type == .weight }?.storedID == weight.storedID)
    }

    @Test func weightAndRepsNeedsRoomForBoth() {
        var drafts = plain()
        drafts.becomeCustom()
        for _ in 0..<(ExerciseDefinition.maxFields - 1) {
            drafts.add(.number)
        }
        #expect(!drafts.canBecomeWeightAndReps)
        drafts.becomeWeightAndReps()
        #expect(drafts.active.allSatisfy { !$0.type.isStandard })

        drafts.remove(drafts.active[0].id)
        #expect(drafts.canBecomeWeightAndReps)
    }

    // MARK: Adding and removing

    @Test func addFieldOffersWeightAndRepsOnlyUnderCustomAndOnlyOnce() {
        var drafts = plain()
        #expect(drafts.addableTypes(for: .weightAndReps) == FieldType.custom)

        drafts.becomeCustom()
        #expect(drafts.addableTypes(for: .custom) == FieldType.standard + FieldType.custom)
        drafts.add(.reps)
        #expect(drafts.addableTypes(for: .custom) == [.weight] + FieldType.custom)
    }

    @Test func aStandardFieldComesOnceWithItsFixedName() {
        var drafts = plain()
        drafts.becomeCustom()
        let reps = drafts.add(.reps)
        #expect(reps?.label == "Reps")
        #expect(reps?.key == FieldType.reps.standardKey)
        let again = drafts.add(.reps)
        #expect(again == nil)
        #expect(drafts.active.count == 1)
    }

    @Test func nothingIsAddedPastTheLimit() {
        var drafts = plain()
        for _ in 0..<(ExerciseDefinition.maxFields - 2) {
            let added = drafts.add(.number)
            #expect(added != nil)
        }
        #expect(drafts.isFull)
        let past = drafts.add(.number)
        #expect(past == nil)
        #expect(drafts.active.count == ExerciseDefinition.maxFields)
    }

    @Test func aNewFieldNeverReusesAKey() throws {
        var drafts = ExerciseFieldDrafts([stored(.number, key: "f7")], keysInUse: ["f7"])
        let next = drafts.add(.time)
        #expect(next?.key == "f8")

        var fresh = ExerciseFieldDrafts([], keysInUse: [])
        let added = fresh.add(.number)
        let first = try #require(added)
        fresh.remove(first.id)
        let second = fresh.add(.number)
        #expect(second?.key != first.key)
    }

    @Test func aDraftGoesAndAStoredFieldIsOnlyMarkedAndCanComeBack() throws {
        let kept = stored(.number, key: "f2")
        var drafts = ExerciseFieldDrafts([kept], keysInUse: ["f2"])
        let new = drafts.add(.text)
        drafts.remove(try #require(new).id)
        #expect(drafts.all.count == 1)

        drafts.remove(kept.id)
        #expect(drafts.all.count == 1)
        #expect(drafts.active.isEmpty)

        drafts.remove(kept.id)
        #expect(drafts.active.count == 1)
    }

    @Test func standardFieldsLeadWhateverOrderTheyCameIn() {
        var drafts = plain()
        drafts.becomeCustom()
        drafts.add(.time)
        drafts.add(.reps)
        drafts.add(.weight)
        #expect(types(drafts.activeInSetOrder) == [.weight, .reps, .time])
    }

    @Test func anUntitledFieldIsNoticedAndNotLabelled() throws {
        var drafts = plain()
        let added = drafts.add(.number)
        var field = try #require(added)
        #expect(drafts.hasUntitled)
        #expect(drafts.labelled.count == 2)

        field.label = "Tempo"
        drafts.update(field)
        #expect(!drafts.hasUntitled)
        #expect(drafts.labelled.count == 3)
    }

    // MARK: Preview

    @Test func anExerciseWithSetsPreviewsThreeNumberedOnes() {
        let preview = ExercisePreview(fields: [("Weight", .weight), ("Reps", .reps)], tracksSets: true, weightSymbol: "kg")
        #expect(preview.rows.map(\.number) == [1, 2, 3])
        #expect(preview.rows[0].cells == [.init(title: nil, value: "80 kg"), .init(title: nil, value: "8 reps")])
        #expect(preview.rows[2].cells != preview.rows[0].cells)
    }

    @Test func anExerciseWithoutSetsPreviewsOneRowWithoutANumber() {
        let preview = ExercisePreview(fields: [("Distance", .number)], tracksSets: false, weightSymbol: "kg")
        #expect(preview.rows.map(\.number) == [nil])
        #expect(preview.rows[0].cells == [.init(title: "Distance", value: "12")])
    }

    @Test func thePreviewUsesTheWeightUnitAndNamesAnUntitledFieldByItsKind() {
        let preview = ExercisePreview(fields: [("Weight", .weight), ("  ", .time)], tracksSets: true, weightSymbol: "lb")
        #expect(preview.rows[0].cells == [.init(title: nil, value: "80 lb"), .init(title: "Duration", value: "1:30")])
    }

    @Test func noFieldsPreviewNothing() {
        #expect(ExercisePreview(fields: [], tracksSets: true, weightSymbol: "kg").rows.isEmpty)
    }
}
