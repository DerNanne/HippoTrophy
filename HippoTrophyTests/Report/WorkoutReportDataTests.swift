import Foundation
import Testing
@testable import HippoTrophy

/// The workout report's numbers, from plain values: which exercises it prints,
/// how volume counts per mode, how sides split, and how blocks fill pages.
@MainActor
struct WorkoutReportDataTests {
    private func set(_ number: Int, _ weight: Double, _ reps: Int, side: SetSide = .both, effort: SetEffort? = nil, position: Int? = nil) -> WorkoutReportData.LoggedSet {
        .init(id: UUID(), number: number, side: side, weightKg: weight, reps: reps, effort: effort, position: position)
    }

    private func entry(_ name: String, mode: UnilateralMode = .bilateral, weightAndReps: Bool = true, notes: String = "", scale: EffortScale = .levels, superset: UUID? = nil, _ sets: [WorkoutReportData.LoggedSet]) -> WorkoutReportData.Entry {
        .init(id: UUID(), name: name, notes: notes, mode: mode, logsWeightAndReps: weightAndReps, effortScale: scale, supersetID: superset, sets: sets)
    }

    /// The report's single superset, or a failed expectation.
    private func onlySuperset(of data: WorkoutReportData) throws -> WorkoutReportData.Superset {
        var found: WorkoutReportData.Superset?
        if data.items.count == 1, case .superset(let superset) = data.items[0] {
            found = superset
        }
        return try #require(found, "expected one superset, got \(names(data.items))")
    }

    private func names(_ items: [WorkoutReportData.Item]) -> [String] {
        items.map { item in
            switch item {
            case .exercise(let exercise): exercise.name
            case .superset(let superset): "\(superset.a.name) + \(superset.b.name)"
            }
        }
    }

    private func report(_ entries: [WorkoutReportData.Entry], name: String = "Push", notes: String = "") -> WorkoutReportData {
        WorkoutReportData(name: name, date: .now, notes: notes, entries: entries, unit: .kilograms)
    }

    @Test func printsOnlyWeightAndRepsAndCountsWhatItLeftOut() {
        let data = report([
            entry("Bench", [set(1, 60, 8), set(2, 60, 6)]),
            entry("Run", weightAndReps: false, [set(1, 0, 0)]),
            entry("Row", [set(1, 50, 10)]),
        ])
        #expect(data.exercises.map(\.name) == ["Bench", "Row"])
        #expect(data.exerciseCount == 2)
        #expect(data.setCount == 3)
        #expect(data.skippedNames == ["Run"])
    }

    /// An exercise that reaches the report without a set was not trained —
    /// whatever its fields, it is no gap in the report to admit.
    @Test func anExerciseWithoutASetIsNeitherPrintedNorMissed() {
        let data = report([
            entry("Bench", [set(1, 60, 8)]),
            entry("Lat Pulldown", weightAndReps: false, []),
            entry("Row", notes: "skipped, shoulder", []),
        ])
        #expect(data.exercises.map(\.name) == ["Bench"])
        #expect(data.exerciseCount == 1)
        #expect(data.setCount == 1)
        #expect(data.skippedNames.isEmpty)
    }

    @Test func aOneSidedLogCountsTwiceAndLeftRightCountsAsLogged() {
        let data = report([
            entry("Squat", [set(1, 100, 5)]),                                            // 500
            entry("Lunge", mode: .oneSided, [set(1, 20, 10)]),                           // 200 × 2
            entry("Curl", mode: .perSide, [set(1, 10, 10, side: .left), set(1, 12, 10, side: .right)]), // 100 + 120
        ])
        #expect(data.totalVolume == 500 + 400 + 220)
    }

    @Test func eachModeSaysItsVolumeItsOwnWay() {
        let data = report([
            entry("Squat", [set(1, 100, 5)]),
            entry("Lunge", mode: .oneSided, [set(1, 20, 10)]),
            entry("Curl", mode: .perSide, [set(1, 10, 10, side: .left), set(1, 12, 10, side: .right)]),
            entry("Plank Hold", [set(1, 0, 10)]),
        ])
        #expect(data.exercises[0].volumeText == "Volume 500 kg")
        #expect(data.exercises[1].volumeText == "Volume 200 kg per side · 400 kg total")
        #expect(data.exercises[2].volumeText == "Volume L 100 kg · R 120 kg")
        #expect(data.exercises[3].volumeText == nil)
    }

    @Test func leftRightSetsGoToTheirOwnTables() {
        let left = set(1, 10, 10, side: .left)
        let right = set(1, 12, 8, side: .right)
        let exercise = report([entry("Curl", mode: .perSide, [left, right])]).exercises[0]
        #expect(exercise.leftSets == [left])
        #expect(exercise.rightSets == [right])
        #expect(exercise.sets.isEmpty)
    }

    @Test func aBlankNameIsCalledWorkoutAndNotesAreTrimmed() {
        let data = report([entry("Bench", notes: "  wide grip \n", [set(1, 60, 8)])], name: "  ", notes: " felt good ")
        #expect(data.title == "Workout")
        #expect(data.notes == "felt good")
        #expect(data.exercises[0].notes == "wide grip")
    }

    /// The legend explains what the printed sets were rated on, and nothing
    /// when no printed set was rated.
    @Test func theLegendFollowsThePrintedRatings() {
        #expect(report([entry("Bench", [set(1, 60, 8)])]).effortScales.isEmpty)
        #expect(report([entry("Bench", [set(1, 60, 8), set(2, 60, 6, effort: .level(.hard))])]).effortScales == [.levels])
    }

    @Test func aWorkoutRatedOnBothScalesExplainsBothInTheOrderTheyAppear() {
        let data = report([
            entry("Squat", scale: .rir, [set(1, 100, 5, effort: .rir(2))]),
            entry("Bench", [set(1, 60, 8, effort: .level(.easy))]),
            entry("Row", scale: .rir, [set(1, 50, 10, effort: .rir(0))]),
        ])
        #expect(data.effortScales == [.rir, .levels])
    }

    /// An exercise that rates nothing has no effort column; one that rates
    /// keeps it even when no set got a rating.
    @Test func onlyAnExerciseThatRatesHasAnEffortColumn() {
        let data = report([
            entry("Bench", scale: .off, [set(1, 60, 8)]),
            entry("Row", scale: .levels, [set(1, 50, 10)]),
        ])
        #expect(data.exercises.map(\.showsEffort) == [false, true])
    }

    @Test func aRatingTheReportDoesNotPrintNeedsNoLegend() {
        let data = report([
            entry("Bench", [set(1, 60, 8)]),
            entry("Run", weightAndReps: false, [set(1, 0, 0, effort: .level(.easy))]),
        ])
        #expect(data.effortScales.isEmpty)
    }

    // MARK: Supersets

    /// "Push A" from the coverage backup: Pull-Up and Cable Fly, done
    /// A B A A B. One table in that order, each set with its letter.
    @Test func aSupersetIsOneBlockInTheOrderItWasDone() throws {
        let pair = UUID()
        let data = report([
            entry("Pull-Up", superset: pair, [set(1, 0, 10, position: 1), set(2, 5, 8, position: 3), set(3, 10, 6, position: 4)]),
            entry("Cable Fly", superset: pair, [set(1, 11.25, 12, position: 2), set(2, 11.25, 12, position: 5)]),
        ])
        let superset = try onlySuperset(of: data)
        #expect(superset.a.name == "Pull-Up")
        #expect(superset.b.name == "Cable Fly")
        #expect(superset.rows.map(\.label) == ["A1", "B1", "A2", "A3", "B2"])
        #expect(superset.rows.map(\.member) == [.a, .b, .a, .a, .b])
    }

    /// The summary counts a superset as the two exercises it is.
    @Test func aSupersetCountsAsTwoExercisesWithTheirOwnVolume() throws {
        let pair = UUID()
        let data = report([
            entry("Dumbbell Row", mode: .oneSided, superset: pair, [set(1, 20, 10, position: 1)]),
            entry("Curl", superset: pair, [set(1, 10, 10, position: 2)]),
        ])
        let superset = try onlySuperset(of: data)
        #expect(data.exerciseCount == 2)
        #expect(data.setCount == 2)
        #expect(data.totalVolume == 400 + 100)
        #expect(superset.a.volumeText == "Volume 200 kg per side · 400 kg total")
        #expect(superset.b.volumeText == "Volume 100 kg")
    }

    /// Where the editor shows it: at its upper exercise, even with something
    /// else between the two.
    @Test func aSupersetStandsWhereItsUpperExerciseDoes() {
        let pair = UUID()
        let data = report([
            entry("Bench", [set(1, 60, 8)]),
            entry("Curl", superset: pair, [set(1, 10, 10, position: 1)]),
            entry("Squat", [set(1, 100, 5)]),
            entry("Pushdown", superset: pair, [set(1, 20, 12, position: 2)]),
        ])
        #expect(names(data.items) == ["Bench", "Curl + Pushdown", "Squat"])
        #expect(data.exercises.map(\.name) == ["Bench", "Curl", "Pushdown", "Squat"])
    }

    /// "Push A" again: Push-Up logs only reps, so the report cannot print
    /// it. Dumbbell Row stands alone and says what it was trained with.
    @Test func anExerciseWhosePartnerIsNotPrintedNamesIt() {
        let pair = UUID()
        let data = report([
            entry("Dumbbell Row", superset: pair, [set(1, 32.5, 10, position: 1), set(2, 32.5, 10, position: 3)]),
            entry("Push-Up", weightAndReps: false, superset: pair, [set(1, 0, 20, position: 2)]),
        ])
        #expect(names(data.items) == ["Dumbbell Row"])
        #expect(data.exercises[0].supersetPartner == "Push-Up")
        #expect(data.skippedNames == ["Push-Up"])
    }

    /// A partner added and never trained was no part of the workout.
    @Test func aPartnerNeverTrainedLeavesNoTrace() {
        let pair = UUID()
        let data = report([
            entry("Curl", superset: pair, [set(1, 10, 10, position: 1)]),
            entry("Pushdown", superset: pair, []),
        ])
        #expect(names(data.items) == ["Curl"])
        #expect(data.exercises[0].supersetPartner == nil)
    }

    @Test func theSharedTableRatesWhenEitherExerciseDoes() throws {
        let pair = UUID()
        let rated = try onlySuperset(of: report([
            entry("Curl", scale: .off, superset: pair, [set(1, 10, 10, position: 1)]),
            entry("Pushdown", scale: .rir, superset: pair, [set(1, 20, 12, effort: .rir(2), position: 2)]),
        ]))
        #expect(rated.showsEffort)

        let unrated = try onlySuperset(of: report([
            entry("Curl", scale: .off, superset: pair, [set(1, 10, 10, position: 1)]),
            entry("Pushdown", scale: .off, superset: pair, [set(1, 20, 12, position: 2)]),
        ]))
        #expect(!unrated.showsEffort)
    }

    /// The editor offers no left/right in a superset, but a set logged for
    /// one side before the two were paired keeps it — and in one shared table
    /// the side has to be in the label.
    @Test func aSetForOneSideSaysWhichInTheSharedTable() throws {
        let pair = UUID()
        let superset = try onlySuperset(of: report([
            entry("Curl", mode: .perSide, superset: pair, [set(1, 10, 10, side: .left, position: 1), set(1, 10, 10, side: .right, position: 2)]),
            entry("Pushdown", superset: pair, [set(1, 20, 12, position: 3)]),
        ]))
        #expect(superset.rows.map(\.label) == ["A1 L", "A1 R", "B1"])
    }

    @Test func pagesFillGreedilyAndNeverSplitABlock() {
        #expect(WorkoutReportRenderer.pack(heights: [40, 40, 30, 50], limit: 100) == [0..<2, 2..<4])
        #expect(WorkoutReportRenderer.pack(heights: [50, 50, 1], limit: 100) == [0..<2, 2..<3])
    }

    @Test func aBlockTallerThanAPageGetsAPageOfItsOwn() {
        #expect(WorkoutReportRenderer.pack(heights: [20, 250, 20], limit: 100) == [0..<1, 1..<2, 2..<3])
    }

    @Test func nothingToPrintIsStillOnePage() {
        #expect(WorkoutReportRenderer.pack(heights: [], limit: 100) == [0..<0])
    }

    /// An assisted set is printed with its help and adds nothing to the
    /// volume — it has no weight.
    @Test func anAssistedSetPrintsItsHelpAndAddsNoVolume() {
        var assisted = set(1, 0, 8)
        assisted.assistanceKg = 25
        let data = report([entry("Pull-Up", [assisted, set(2, 10, 5)])])

        #expect(data.totalVolume == 50)
        #expect(ReportFormat.load(of: assisted, in: .kilograms) == WeightUnit.kilograms.formatted(kilograms: 25) + " assist")
        #expect(ReportFormat.load(of: set(2, 10, 5), in: .kilograms) == WeightUnit.kilograms.formatted(kilograms: 10))
    }
}
