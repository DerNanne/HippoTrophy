import Foundation
import SwiftData
import Testing
@testable import HippoTrophy

/// The numbers behind an exercise's progress graph.
@MainActor
struct ExerciseProgressTests {
    private typealias LoggedSet = ExerciseProgress.LoggedSet

    private func day(_ number: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(number) * 86_400)
    }

    private func session(
        on number: Int,
        mode: UnilateralMode = .bilateral,
        workoutID: UUID = UUID(),
        _ sets: [(Double, Int)],
        side: SetSide = .both
    ) -> ExerciseProgress.Session {
        ExerciseProgress.Session(
            workoutID: workoutID,
            date: day(number),
            mode: mode,
            sets: sets.map { LoggedSet(side: side, weightKg: $0.0, reps: $0.1) }
        )
    }

    // MARK: The estimate

    @Test func theEstimateFollowsEpleyAndASingleIsItsOwnMax() {
        #expect(ExerciseProgress.estimatedMax(weightKg: 60, reps: 8) == 76)
        #expect(ExerciseProgress.estimatedMax(weightKg: 75, reps: 6) == 90)
        #expect(ExerciseProgress.estimatedMax(weightKg: 100, reps: 1) == 100)
    }

    @Test func warmUpsDoNotPullTheEstimateDown() throws {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(40, 10), (60, 8), (60, 8), (60, 7)])
        ])

        let point = try #require(progress.points(for: .estimatedMax).first)
        #expect(point.value == 76)
        #expect(point.bestSet == LoggedSet(side: .both, weightKg: 60, reps: 8))
        #expect(point.setCount == 4)
    }

    @Test func moreRepsAtTheSameWeightShowInTheEstimateButNotInTheTopWeight() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(40, 10), (60, 8), (60, 8), (60, 7)]),
            session(on: 8, [(40, 10), (60, 10), (60, 9), (60, 8)])
        ])

        #expect(progress.points(for: .maxWeight).map(\.value) == [60, 60])
        #expect(progress.points(for: .estimatedMax).map(\.value) == [76, 80])
    }

    // MARK: The other metrics

    @Test func theTopWeightShowsItsBestSetByReps() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(80, 3), (80, 5), (70, 8)])])

        let point = progress.points(for: .maxWeight).first
        #expect(point?.value == 80)
        #expect(point?.bestSet?.reps == 5)
    }

    @Test func theVolumeAddsUpEverySetAndNamesNoneOfThem() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(40, 10), (60, 8), (60, 8), (60, 7)])])

        let point = progress.points(for: .volume).first
        #expect(point?.value == 1780)
        #expect(point?.bestSet == nil)
    }

    @Test func theMostRepsShowTheHeavierSetOfATie() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(0, 12), (10, 12), (20, 8)])])

        let point = progress.points(for: .mostReps).first
        #expect(point?.value == 12)
        #expect(point?.bestSet?.weightKg == 10)
    }

    // MARK: What counts

    @Test func aSetWithoutARepIsNotALift() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(100, 0), (60, 5)])])

        #expect(progress.points(for: .maxWeight).first?.value == 60)
        #expect(progress.points(for: .estimatedMax).first?.setCount == 1)
    }

    @Test func aHistoryWithoutAnyLiftOffersNothing() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(60, 0)])])

        #expect(progress.metrics.isEmpty)
        #expect(progress.metric(preferring: .estimatedMax) == nil)
    }

    @Test func bodyweightOnlyOffersTheMostRepsAndPicksThemOverThePreference() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(0, 8), (0, 6)]),
            session(on: 3, [(0, 9)])
        ])

        #expect(progress.metrics == [.mostReps])
        #expect(progress.metric(preferring: .estimatedMax) == .mostReps)
        #expect(progress.points(for: .mostReps).map(\.value) == [8, 9])
    }

    @Test func aWeightedSetOffersEverythingAndKeepsThePreference() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(0, 8)]),
            session(on: 3, [(10, 5)])
        ])

        #expect(progress.metrics == [.estimatedMax, .maxWeight, .volume, .mostReps])
        #expect(progress.metric(preferring: .volume) == .volume)
        // The bodyweight day has no weight to plot and no point, not a zero.
        #expect(progress.points(for: .maxWeight).map(\.date) == [day(3)])
        #expect(progress.points(for: .mostReps).map(\.date) == [day(1), day(3)])
    }

    // MARK: Workouts and lines

    @Test func twoEntriesInOneWorkoutAreOnePoint() {
        let workout = UUID()
        let progress = ExerciseProgress(sessions: [
            session(on: 1, workoutID: workout, [(60, 8)]),
            session(on: 1, workoutID: workout, [(70, 5), (50, 12)])
        ])

        let estimate = progress.points(for: .estimatedMax)
        #expect(estimate.count == 1)
        #expect(estimate.first?.bestSet?.weightKg == 70)
        // 480 + 350 + 600
        #expect(progress.points(for: .volume).first?.value == 1430)
    }

    @Test func pointsRunOldestFirstWhateverOrderTheEntriesCameIn() {
        let progress = ExerciseProgress(sessions: [
            session(on: 9, [(70, 5)]),
            session(on: 2, [(60, 5)]),
            session(on: 5, [(65, 5)])
        ])

        #expect(progress.points(for: .maxWeight).map(\.value) == [60, 65, 70])
    }

    @Test func anLRLogDrawsALeftAndARightLine() {
        let workout = UUID()
        let progress = ExerciseProgress(sessions: [
            ExerciseProgress.Session(workoutID: workout, date: day(1), mode: .perSide, sets: [
                LoggedSet(side: .right, weightKg: 22, reps: 10),
                LoggedSet(side: .left, weightKg: 20, reps: 10),
                LoggedSet(side: .left, weightKg: 20, reps: 8)
            ])
        ])

        let points = progress.points(for: .maxWeight)
        #expect(points.map(\.line) == [.left, .right])
        #expect(points.map(\.value) == [20, 22])
        #expect(progress.points(for: .volume).map(\.value) == [360, 220])
    }

    @Test func oneSidedAndTwoSidedShareALineAndKeepTheirMode() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, mode: .bilateral, [(40, 10)]),
            session(on: 3, mode: .oneSided, [(20, 10)])
        ])

        let points = progress.points(for: .maxWeight)
        #expect(points.map(\.line) == [.both, .both])
        #expect(points.map(\.mode) == [.bilateral, .oneSided])
        // Per side, as logged: not doubled into what both sides moved.
        #expect(progress.points(for: .volume).map(\.value) == [400, 200])
    }

    // MARK: What a tapped point says

    private let german = Locale(identifier: "de_DE")

    @Test func anEstimateIsRoundedToTheWholeUnit() {
        #expect(ProgressMetric.estimatedMax.text(81.67, unit: .kilograms, locale: german) == "≈ 82 kg")
        #expect(ProgressMetric.estimatedMax.text(100, unit: .pounds, locale: german) == "≈ 220 lb")
    }

    @Test func aLoggedWeightKeepsItsFraction() {
        #expect(ProgressMetric.maxWeight.text(62.5, unit: .kilograms, locale: german) == "62,5 kg")
    }

    @Test func aVolumeGroupsItsThousands() {
        #expect(ProgressMetric.volume.text(1780, unit: .kilograms, locale: german) == "1.780 kg")
    }

    @Test func repsAreCounted() {
        #expect(ProgressMetric.mostReps.text(1, unit: .kilograms) == "1 rep")
        #expect(ProgressMetric.mostReps.text(12, unit: .kilograms) == "12 reps")
    }

    @Test func aPointNamesItsSetOrHowManySets() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(62.5, 6), (60, 8), (0, 15)])])

        #expect(progress.points(for: .maxWeight).first?.sourceText(unit: .kilograms, locale: german) == "62,5 kg × 6")
        // Without a weight the set would only repeat the reps the value says.
        #expect(progress.points(for: .mostReps).first?.sourceText(unit: .kilograms, locale: german) == .some(nil))
        #expect(progress.points(for: .volume).first?.sourceText(unit: .kilograms, locale: german) == "3 sets")
    }

    @Test func aTapFindsTheClosestWorkoutWithBothItsSides() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(40, 10)]),
            ExerciseProgress.Session(workoutID: UUID(), date: day(10), mode: .perSide, sets: [
                LoggedSet(side: .left, weightKg: 20, reps: 10),
                LoggedSet(side: .right, weightKg: 22, reps: 10)
            ])
        ])
        let points = progress.points(for: .maxWeight)

        #expect(ExerciseProgress.points(nearest: day(4), in: points).map(\.value) == [40])
        #expect(ExerciseProgress.points(nearest: day(7), in: points).map(\.line) == [.left, .right])
        #expect(ExerciseProgress.points(nearest: day(7), in: []).isEmpty)
    }

    // MARK: The axes

    @Test func aSingleValueGetsRoomAroundIt() {
        #expect(ExerciseProgress.valueDomain(of: [40]) == 36...44)
        #expect(ExerciseProgress.valueDomain(of: [10, 10, 10]) == 9...11)
        #expect(ExerciseProgress.valueDomain(of: [5]) == 4...6)
    }

    @Test func spreadValuesLeaveTheAxisToTheChart() {
        #expect(ExerciseProgress.valueDomain(of: [60, 62.5]) == nil)
        #expect(ExerciseProgress.valueDomain(of: []) == nil)
    }

    @Test func aSingleWorkoutStandsInTheMiddleOfAWeek() {
        let domain = ExerciseProgress.dateDomain(of: [day(10)])
        #expect(domain == day(10).addingTimeInterval(-3.5 * 86_400)...day(10).addingTimeInterval(3.5 * 86_400))
        #expect(ExerciseProgress.dateDomain(of: [day(10), day(12)])?.contains(day(8)) == true)
    }

    @Test func aLongerHistoryLeavesTheTimeAxisToTheChart() {
        #expect(ExerciseProgress.dateDomain(of: [day(1), day(8)]) == nil)
        #expect(ExerciseProgress.dateDomain(of: []) == nil)
    }

    // MARK: Reading the store

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func addSet(
        to entry: ExerciseEntry,
        number: Int,
        side: SetSide = .both,
        weight: Double?,
        reps: Double?,
        withWeightField: Bool = true,
        in context: ModelContext
    ) {
        let set = SetEntry(setNumber: number, sideRawValue: side.rawValue, exercise: entry)
        context.insert(set)
        if withWeightField {
            context.insert(FieldValue(fieldKey: "weight", label: "Weight", typeRawValue: "weight", orderIndex: 0, numberValue: weight, set: set))
        }
        context.insert(FieldValue(fieldKey: "reps", label: "Reps", typeRawValue: "reps", orderIndex: 1, numberValue: reps, set: set))
    }

    @Test func readingEntriesCountsTheSetsTheHistoryShows() throws {
        let context = try context()
        let workout = WorkoutSession(date: day(4))
        context.insert(workout)

        let lr = ExerciseEntry(name: "Row", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        lr.unilateralMode = .perSide
        context.insert(lr)
        addSet(to: lr, number: 1, side: .left, weight: 20, reps: 10, in: context)
        addSet(to: lr, number: 2, side: .right, weight: 22, reps: 10, in: context)
        // A shared set in an L/R log is not on the page, so not on the graph.
        addSet(to: lr, number: 3, side: .both, weight: 90, reps: 10, in: context)
        // Reps alone are not a set of weight training.
        addSet(to: lr, number: 4, side: .left, weight: nil, reps: 30, withWeightField: false, in: context)

        let orphan = ExerciseEntry(name: "Row", orderIndex: 1, definitionID: UUID(), effortScale: .off)
        context.insert(orphan)
        addSet(to: orphan, number: 1, weight: 100, reps: 5, in: context)

        let progress = ExerciseProgress(entries: [lr, orphan])
        #expect(progress.sessions.count == 1)
        #expect(progress.sessions.first?.sets.map(\.weightKg) == [20, 22])
        #expect(progress.points(for: .maxWeight).map(\.value) == [20, 22])
    }

    @Test func anEmptyWeightReadsAsBodyweight() throws {
        let context = try context()
        let workout = WorkoutSession(date: day(1))
        context.insert(workout)
        let entry = ExerciseEntry(name: "Pull-Up", orderIndex: 0, definitionID: UUID(), effortScale: .off, session: workout)
        context.insert(entry)
        addSet(to: entry, number: 1, weight: nil, reps: 8, in: context)

        let progress = ExerciseProgress(entries: [entry])
        #expect(progress.metrics == [.mostReps])
        #expect(progress.points(for: .mostReps).first?.value == 8)
    }

    // MARK: Assistance

    private func assisted(on number: Int, _ sets: [(Double, Int)]) -> ExerciseProgress.Session {
        ExerciseProgress.Session(
            workoutID: UUID(),
            date: day(number),
            mode: .bilateral,
            sets: sets.map { LoggedSet(side: .both, weightKg: 0, reps: $0.1, assistanceKg: $0.0) }
        )
    }

    /// The way from the machine to added weight is one line: help below zero,
    /// bodyweight at zero, weight above.
    @Test func helpIsALoadBelowZeroAndBodyweightIsZero() {
        let progress = ExerciseProgress(sessions: [
            assisted(on: 1, [(35, 8), (30, 6)]),
            assisted(on: 8, [(20, 8)]),
            session(on: 15, [(0, 5)]),
            session(on: 22, [(0, 6), (10, 4)])
        ])

        #expect(progress.countsAssistance)
        #expect(progress.points(for: .maxWeight).map(\.value) == [-30, -20, 0, 10])
    }

    @Test func aHistoryOfHelpAloneOffersTheLoadAndTheReps() {
        let progress = ExerciseProgress(sessions: [assisted(on: 1, [(35, 8)]), assisted(on: 8, [(25, 8)])])
        #expect(progress.metrics == [.maxWeight, .mostReps])
    }

    /// The one-rep max and the volume add up weight, and an assisted set has
    /// none: it gives them nothing, rather than a negative number.
    @Test func helpGivesTheEstimateAndTheVolumeNothing() {
        let progress = ExerciseProgress(sessions: [
            assisted(on: 1, [(35, 8)]),
            session(on: 8, [(10, 5)])
        ])

        #expect(progress.metrics == [.estimatedMax, .maxWeight, .volume, .mostReps])
        #expect(progress.points(for: .volume).map(\.value) == [50])
        #expect(progress.points(for: .estimatedMax).count == 1)
    }

    /// Without help in the history, bodyweight sets stay off the weight
    /// line, as they always were.
    @Test func withoutHelpBodyweightIsStillNoWeight() {
        let progress = ExerciseProgress(sessions: [session(on: 1, [(0, 8)]), session(on: 8, [(10, 5)])])
        #expect(!progress.countsAssistance)
        #expect(progress.points(for: .maxWeight).map(\.value) == [10])
    }

    @Test func anAssistedPointSaysTheHelpItCameFrom() throws {
        let progress = ExerciseProgress(sessions: [assisted(on: 1, [(25, 8)])])
        let point = try #require(progress.points(for: .maxWeight).first)
        #expect(point.sourceText(unit: .kilograms, locale: Locale(identifier: "en_US")) == "25 kg assist × 8")
    }

    @Test func aSingleValueBelowZeroStillGetsAnAxisAroundIt() throws {
        let domain = try #require(ExerciseProgress.valueDomain(of: [-20]))
        #expect(domain.contains(-20))
        #expect(domain.lowerBound < -20)
    }

    // MARK: Personal records

    @Test func theRecordIsTheHeaviestWeightWhateverTheReps() throws {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(60, 12)]),
            session(on: 8, [(70, 3), (65, 10)]),
            session(on: 15, [(65, 12)])
        ])

        let record = try #require(progress.records.first)
        #expect(progress.records.count == 1)
        #expect(record.set == LoggedSet(side: .both, weightKg: 70, reps: 3))
        #expect(record.date == day(8))
    }

    @Test func atTheSameWeightMoreRepsBeatFewer() throws {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(65, 8)]),
            session(on: 8, [(65, 10), (65, 9)]),
            session(on: 15, [(65, 9)])
        ])

        let record = try #require(progress.records.first)
        #expect(record.set.reps == 10)
        #expect(record.date == day(8))
    }

    @Test func repeatingTheRecordLeavesItWithTheWorkoutThatGotThereFirst() throws {
        // Handed over newest first, the way the history lists them.
        let progress = ExerciseProgress(sessions: [
            session(on: 15, [(65, 10)]),
            session(on: 8, [(65, 10)])
        ])

        #expect(try #require(progress.records.first).date == day(8))
    }

    @Test func withoutWeightTheMostRepsAreTheRecord() throws {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(0, 10), (0, 8)]),
            session(on: 8, [(0, 4), (0, 6)]),
            session(on: 15, [(0, 10)])
        ])

        let record = try #require(progress.records.first)
        #expect(record.set == LoggedSet(side: .both, weightKg: 0, reps: 10))
        #expect(record.date == day(1))
        #expect(record.setText(unit: .kilograms) == "10 reps")
    }

    @Test func oneWeightedSetOutranksAnyNumberOfRepsWithout() throws {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(0, 20)]),
            session(on: 8, [(5, 3)])
        ])

        #expect(try #require(progress.records.first).set.weightKg == 5)
    }

    @Test func setsWithHelpOrWithoutARepSetNoRecord() {
        let progress = ExerciseProgress(sessions: [
            ExerciseProgress.Session(workoutID: UUID(), date: day(2), mode: .bilateral, sets: [
                LoggedSet(side: .both, weightKg: 0, reps: 8, assistanceKg: 20)
            ]),
            session(on: 3, [(80, 0)])
        ])

        #expect(progress.records.isEmpty)
    }

    @Test func sharedAndOneSidedWeightsKeepARecordEachTheNewestFirst() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, [(60, 8)]),
            session(on: 8, mode: .oneSided, [(25, 10)]),
            session(on: 15, mode: .perSide, [(27.5, 6)], side: .left)
        ])

        #expect(progress.records.map(\.set.weightKg) == [27.5, 25, 60])
        #expect(progress.records.map(\.side) == [.left, .right, .both])
        #expect(progress.records.map(\.mode) == [.perSide, .oneSided, .bilateral])
    }

    @Test func anLRLogHasARecordPerSideLeftFirst() {
        let progress = ExerciseProgress(sessions: [
            ExerciseProgress.Session(workoutID: UUID(), date: day(1), mode: .perSide, sets: [
                LoggedSet(side: .left, weightKg: 20, reps: 15),
                LoggedSet(side: .right, weightKg: 7.5, reps: 15),
                LoggedSet(side: .left, weightKg: 20, reps: 12)
            ]),
            ExerciseProgress.Session(workoutID: UUID(), date: day(8), mode: .perSide, sets: [
                LoggedSet(side: .right, weightKg: 10, reps: 8)
            ])
        ])

        #expect(progress.records.map(\.side) == [.left, .right])
        #expect(progress.records.map(\.set.weightKg) == [20, 10])
        #expect(progress.records.map(\.date) == [day(1), day(8)])
    }

    @Test func theSameWeightOnBothSidesCountsForEitherOnceTheSidesAreApart() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, mode: .oneSided, [(15, 10)]),
            ExerciseProgress.Session(workoutID: UUID(), date: day(8), mode: .perSide, sets: [
                LoggedSet(side: .left, weightKg: 20, reps: 10),
                LoggedSet(side: .right, weightKg: 12.5, reps: 10)
            ])
        ])

        #expect(progress.records.map(\.side) == [.left, .right])
        #expect(progress.records.map(\.set.weightKg) == [20, 15])
        #expect(progress.records.map(\.mode) == [.perSide, .oneSided])
    }

    @Test func withoutAnLRLogOneSidedWeightKeepsOneRecord() {
        let progress = ExerciseProgress(sessions: [
            session(on: 1, mode: .oneSided, [(15, 10)])
        ])

        #expect(progress.records.map(\.side) == [.both])
    }

    @Test func theRecordNamesItsSet() {
        let record = ExerciseProgress.Record(date: day(1), mode: .bilateral, set: LoggedSet(side: .both, weightKg: 65, reps: 10))

        #expect(record.setText(unit: .kilograms, locale: Locale(identifier: "en_US")) == "65 kg × 10")
    }
}
