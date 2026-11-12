import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

@MainActor
struct SideLoggingTests {
    private let context: ModelContext

    init() throws {
        context = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// Left 1\u{2013}3 and right 1\u{2013}2, logged apart.
    private func entry(left: Int = 3, right: Int = 2, start: ExerciseSide = .left, session: WorkoutSession? = nil) -> ExerciseEntry {
        let entry = ExerciseEntry(name: "Row", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: session)
        context.insert(entry)
        entry.unilateralMode = .perSide
        entry.startSideRawValue = start.rawValue
        for _ in 0..<left { entry.addSet(on: .left, definition: nil, in: context) }
        for _ in 0..<right { entry.addSet(on: .right, definition: nil, in: context) }
        return entry
    }

    private func names(_ sets: [SetEntry]) -> [String] {
        sets.map { ($0.side == .left ? "L" : "R") + "\($0.setNumber)" }
    }

    // The order following on its own

    @Test func theSidesTakeTurnsFromTheOneItStartsWithAndTheLongerSideRunsOn() {
        #expect(names(entry().setsInOrder()) == ["L1", "R1", "L2", "R2", "L3"])
        #expect(names(entry(start: .right).setsInOrder()) == ["R1", "L1", "R2", "L2", "L3"])
        #expect(names(entry(left: 1, right: 3, start: .left).setsInOrder()) == ["L1", "R1", "R2", "R3"])
    }

    @Test func nothingIsStoredWhileTheOrderFollowsOnItsOwn() {
        let row = entry()
        row.setStartSide(.right)
        #expect(!row.hasChosenOrder)
        #expect(row.sets.allSatisfy { $0.sideOrder == nil })
    }

    @Test func theGuideFollowsTheStartSide() {
        let row = entry(left: 2, right: 2, start: .right)
        #expect(names(WorkoutGuide.order(of: [row])) == ["R1", "L1", "R2", "L2"])
    }

    @Test func nothingSaidStartsLeft() {
        let row = entry(left: 1, right: 1)
        row.startSideRawValue = nil
        #expect(row.startSide == .left)
        #expect(names(row.setsInOrder()) == ["L1", "R1"])
    }

    // The order chosen freely

    @Test func theListIsFreeAcrossTheSides() {
        let row = entry(left: 2, right: 2)
        // L1 R1 L2 R2, with L2 dragged above R1.
        row.moveSetsInList(from: [2], to: 1)
        #expect(names(row.setsInOrder()) == ["L1", "L2", "R1", "R2"])
        #expect(row.hasChosenOrder)
    }

    @Test func aMoveRenumbersItsSideAndLeavesTheOther() {
        let row = entry(left: 2, right: 2)
        let first = row.sets(on: .left)[0]
        row.moveSetsInList(from: [0], to: 3)
        #expect(first.setNumber == 2)
        #expect(first.side == .left)
        #expect(row.sets(on: .right).map(\.setNumber) == [1, 2])
    }

    @Test func theFirstSetSaysWhichSideStarts() {
        let row = entry(left: 2, right: 1)
        // L1 R1 L2, with R1 dragged to the top.
        row.moveSetsInList(from: [1], to: 0)
        #expect(row.startSide == .right)
        #expect(names(row.setsInOrder()) == ["R1", "L1", "L2"])
    }

    @Test func choosingAStartSideMovesItsFirstSetToTheTopOfAChosenOrder() {
        let row = entry(left: 2, right: 2)
        row.moveSetsInList(from: [2], to: 1)
        row.setStartSide(.right)
        #expect(names(row.setsInOrder()) == ["R1", "L1", "L2", "R2"])
        #expect(row.startSide == .right)
    }

    @Test func aChosenOrderKeepsSetsAddedDeletedAndCopied() {
        let row = entry(left: 2, right: 2)
        row.moveSetsInList(from: [2], to: 1)

        row.addSet(on: .right, definition: nil, in: context)
        #expect(names(row.setsInOrder()) == ["L1", "L2", "R1", "R2", "R3"])

        row.copySet(row.sets(on: .left)[0], in: context)
        #expect(names(row.setsInOrder()) == ["L1", "L2", "L3", "R1", "R2", "R3"])

        row.deleteSet(row.sets(on: .left)[0], in: context)
        #expect(names(row.setsInOrder()) == ["L1", "L2", "R1", "R2", "R3"])
    }

    @Test func deletingTheFirstSetOfAChosenOrderHandsOverTheStart() {
        let row = entry(left: 1, right: 1)
        row.moveSetsInList(from: [1], to: 0)
        #expect(row.startSide == .right)
        row.deleteSet(row.sets(on: .right)[0], in: context)
        #expect(row.startSide == .left)
    }

    /// Tabs reorder within a side and leave the other side's places alone.
    @Test func tabsKeepTheOrderAndTheSidesPlaces() {
        let row = entry(left: 2, right: 2)
        row.moveSetsInList(from: [2], to: 1) // L1 L2 R1 R2
        let oldSecondRight = row.sets(on: .right)[1]
        row.moveSets(on: .right, from: [1], to: 0)
        #expect(names(row.setsInOrder()) == ["L1", "L2", "R1", "R2"])
        #expect(row.setsInOrder()[2].id == oldSecondRight.id)
    }

    @Test func leavingLeftAndRightForgetsTheOrder() {
        let row = entry(left: 2, right: 2)
        row.moveSetsInList(from: [2], to: 1)
        row.applyMode(.oneSided)
        #expect(!row.hasChosenOrder)
        #expect(row.startSide == .left)
        row.applyMode(.bilateral)
        #expect(row.startSideRawValue == nil)
    }

    // The side proposed

    @Test func theLastTimeSaysWhichSideIsProposed() {
        let last = entry(start: .right)
        #expect(ExerciseSide.suggested(lastLogged: last) == .right)
        #expect(ExerciseSide.suggested(lastLogged: nil) == .left)
        last.startSideRawValue = nil
        #expect(ExerciseSide.suggested(lastLogged: last) == .left, "logged before there was a place for it")
    }

    private func trained(start: ExerciseSide, date: Date) throws -> WorkoutSession {
        let session = WorkoutSession(name: "Past", date: date)
        context.insert(session)
        let row = entry(left: 1, right: 1, start: start, session: session)
        session.exercises.append(row)
        for set in row.sets {
            set.isDone = true
            let value = FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: FieldType.reps.rawValue, orderIndex: 0, numberValue: 8, set: set)
            set.values.append(value)
            context.insert(value)
        }
        try context.save()
        return session
    }

    /// Changed in one workout, proposed for the next, read from the workouts
    /// and not from anywhere else.
    @Test func aCopyProposesTheSideOfTheLastTime() throws {
        _ = try trained(start: .left, date: Date(timeIntervalSinceReferenceDate: 1_000))
        let last = try trained(start: .right, date: Date(timeIntervalSinceReferenceDate: 2_000))

        let copy = last.trainingCopy(dated: .now, in: context)
        #expect(copy.exercises.first?.startSide == .right)

        let older = WorkoutSession(name: "Plan", date: .now)
        context.insert(older)
        let planned = entry(left: 1, right: 1, start: .left, session: older)
        older.exercises.append(planned)
        #expect(older.trainingCopy(dated: .now, in: context).exercises.first?.startSide == .right)
    }

    @Test func aCopyKeepsAnOrderChosenFreely() throws {
        _ = try trained(start: .left, date: Date(timeIntervalSinceReferenceDate: 1_000))
        let plan = WorkoutSession(name: "Plan", date: .now)
        context.insert(plan)
        let planned = entry(left: 2, right: 1, start: .right, session: plan)
        plan.exercises.append(planned)
        planned.moveSetsInList(from: [1], to: 0) // L1 R1 L2 (start right: R1 L1 L2 -> L1 R1 L2)
        let before = names(planned.setsInOrder())

        let copied = try #require(plan.trainingCopy(dated: .now, in: context).exercises.first)
        #expect(names(copied.setsInOrder()) == before)
        #expect(copied.startSide == planned.startSide)
    }

    // A template's say

    private func template(start: ExerciseSide?) -> WorkoutSession {
        let plan = WorkoutSession(name: "Plan", date: .now)
        plan.isTemplate = true
        context.insert(plan)
        let planned = entry(left: 1, right: 1, session: plan)
        planned.startSideRawValue = start?.rawValue
        plan.exercises.append(planned)
        return plan
    }

    @Test func aTemplatesSideComesBeforeTheLastTime() throws {
        _ = try trained(start: .right, date: Date(timeIntervalSinceReferenceDate: 1_000))
        let copy = template(start: .left).trainingCopy(dated: .now, in: context)
        #expect(copy.exercises.first?.startSide == .left)
    }

    @Test func aTemplateSayingNothingGoesByTheLastTime() throws {
        _ = try trained(start: .right, date: Date(timeIntervalSinceReferenceDate: 1_000))
        let copy = template(start: nil).trainingCopy(dated: .now, in: context)
        #expect(copy.exercises.first?.startSide == .right)
    }

    @Test func withoutTemplateOrLastTimeItIsLeftAndSaysSo() {
        let copy = template(start: nil).trainingCopy(dated: .now, in: context)
        #expect(copy.exercises.first?.startSideRawValue == ExerciseSide.left.rawValue)
    }

    @Test func aWorkoutsCopyGoesByTheLastTimeNotByItself() throws {
        let older = try trained(start: .left, date: Date(timeIntervalSinceReferenceDate: 1_000))
        _ = try trained(start: .right, date: Date(timeIntervalSinceReferenceDate: 2_000))
        #expect(older.trainingCopy(dated: .now, in: context).exercises.first?.startSide == .right)
    }

    /// The side one workout happened to start with is no prescription.
    @Test func aTemplateOfAWorkoutPrescribesNoSide() throws {
        let workout = try trained(start: .right, date: Date(timeIntervalSinceReferenceDate: 1_000))
        let made = workout.templateCopy(named: "Plan")
        #expect(made.exercises.first?.startSideRawValue == nil)
        #expect(template(start: .right).templateCopy(named: "Copy").exercises.first?.statedStartSide == .right)
    }

    @Test func aTemplateOfAWorkoutKeepsAnOrderChosenFreely() throws {
        let workout = try trained(start: .left, date: Date(timeIntervalSinceReferenceDate: 1_000))
        let row = try #require(workout.exercises.first)
        row.moveSetsInList(from: [1], to: 0)
        let made = try #require(workout.templateCopy(named: "Plan").exercises.first)
        #expect(made.hasChosenOrder)
        #expect(made.startSide == .right)
    }

    @Test func aTemplateCanTakeItsSayBack() throws {
        let row = try #require(template(start: .right).exercises.first)
        row.setStartSide(nil)
        #expect(row.statedStartSide == nil)
    }

    // The rest between sides

    @Test func theOtherSideOfASetNextIsTheRestBetweenSides() {
        let row = entry(left: 2, right: 2, start: .right)
        let order = row.setsInOrder() // R1 L1 R2 L2
        #expect(row.restKind(after: order[0]) == .betweenSides)
        #expect(row.restKind(after: order[1]) == .afterSet, "on to the next set, even if on the other side")
        #expect(row.restKind(after: order[2]) == .betweenSides)
        #expect(row.restKind(after: order[3]) == .afterSet, "nothing left")
    }

    @Test func aSideWithMoreSetsRestsTheNormalWay() {
        let row = entry(left: 3, right: 1)
        let order = row.setsInOrder() // L1 R1 L2 L3
        #expect(row.restKind(after: order[2]) == .afterSet)
    }

    @Test func anOtherSideAlreadyDoneIsNoReasonToSwitch() {
        let row = entry(left: 1, right: 1)
        let order = row.setsInOrder()
        order[1].isDone = true
        #expect(row.restKind(after: order[0]) == .afterSet)
    }

    @Test func aChosenOrderOfBlocksRestsTheNormalWay() {
        let row = entry(left: 2, right: 2)
        row.moveSetsInList(from: [2], to: 1) // L1 L2 R1 R2
        for set in row.setsInOrder() {
            #expect(row.restKind(after: set) == .afterSet)
        }
    }

    @Test func aChosenOrderKeepingASetsSidesTogetherStillSwitches() {
        let row = entry(left: 2, right: 2)
        row.moveSetsInList(from: [1], to: 0) // R1 L1 L2 R2
        let order = row.setsInOrder()
        #expect(row.restKind(after: order[0]) == .betweenSides)
        #expect(row.restKind(after: order[1]) == .afterSet)
        #expect(row.restKind(after: order[2]) == .betweenSides)
    }

    @Test func onlyLeftAndRightHasThisRest() {
        let row = entry(left: 1, right: 1)
        let first = row.setsInOrder()[0]
        row.unilateralMode = .oneSided
        #expect(row.restKind(after: first) == .afterSet)
    }

    // The workout's page

    @Test func theWorkoutsPageSaysWhatWasSaid() {
        let row = entry(left: 2, right: 1, start: .right)
        #expect(row.sideOrderSummary == "Order: R1 · L1 · L2")

        row.startSideRawValue = nil
        #expect(row.sideOrderSummary == nil, "logged before there was a place for it")

        let same = ExerciseEntry(name: "Curl", orderIndex: 0, definitionID: UUID(), effortScale: .off)
        context.insert(same)
        same.unilateralMode = .oneSided
        #expect(same.sideOrderSummary == nil)
        same.startSideRawValue = ExerciseSide.right.rawValue
        #expect(same.sideOrderSummary == "Started with Right")

        same.unilateralMode = .bilateral
        #expect(same.sideOrderSummary == nil)
    }
}
