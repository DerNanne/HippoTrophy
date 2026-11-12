import CoreGraphics
import Testing
@testable import HippoTrophy

/// The outlines the heat map is drawn from, and what a tap on them finds.
@MainActor
struct BodyOutlineTests {
    @Test func theParserReadsLinesCurvesAndClosedShapes() {
        let path = OutlinePath.parse("M10,10 L30,10 Q40,20 30,30 C20,40 10,30 10,20 Z")
        #expect(path.contains(CGPoint(x: 20, y: 20)))
        #expect(!path.contains(CGPoint(x: 50, y: 50)))
        #expect(path.boundingBoxOfPath.minX == 10)
    }

    @Test func everyPointGoesThroughTheTransformControlPointsIncluded() {
        let path = OutlinePath.parse("M10,10 L30,10 L30,30 Z") { CGPoint(x: 200 - $0.x, y: $0.y) }
        #expect(path.boundingBoxOfPath == CGRect(x: 170, y: 10, width: 20, height: 20))
    }

    @Test func everyMuscleGroupIsDrawnOnBothFigures() {
        for figure in BodyFigure.allCases {
            let drawn = Set(BodySide.allCases.flatMap { BodyOutline.of(figure, $0).muscles.map(\.group) })
            #expect(drawn == Set(MuscleGroup.allCases), "\(figure)")
        }
    }

    @Test func aTapFindsTheMuscleOnEitherHalf() {
        let front = BodyOutline.of(.male, .front)
        #expect(front.muscle(at: CGPoint(x: 85, y: 115)) == .chest)
        #expect(front.muscle(at: CGPoint(x: 115, y: 115)) == .chest)
        #expect(front.muscle(at: CGPoint(x: 92, y: 160)) == .core)

        let back = BodyOutline.of(.male, .back)
        #expect(back.muscle(at: CGPoint(x: 80, y: 262)) == .glutes)
        #expect(back.muscle(at: CGPoint(x: 52, y: 160)) == .triceps)
    }

    /// Shrugs train the trapezius between the neck and the shoulders, rows the
    /// part below; the outline is cut where one ends.
    @Test func theUpperTrapeziusIsTrapsAndBelowItBack() {
        let front = BodyOutline.of(.male, .front)
        #expect(front.muscle(at: CGPoint(x: 80, y: 88)) == .traps)
        #expect(front.muscle(at: CGPoint(x: 120, y: 88)) == .traps)

        let back = BodyOutline.of(.male, .back)
        #expect(back.muscle(at: CGPoint(x: 90, y: 88)) == .traps)
        #expect(back.muscle(at: CGPoint(x: 110, y: 88)) == .traps)
        #expect(back.muscle(at: CGPoint(x: 97, y: 130)) == .back)
    }

    @Test func aTapInTheCutBetweenTwoPiecesTakesTheOneBeside() {
        #expect(BodyOutline.of(.male, .back).muscle(at: CGPoint(x: 100, y: 262)) == .glutes)
    }

    @Test func theHeadAndTheSpaceBesideTheFigureAreNoMuscle() {
        let front = BodyOutline.of(.male, .front)
        #expect(front.muscle(at: CGPoint(x: 100, y: 36)) == nil)
        #expect(front.muscle(at: CGPoint(x: 5, y: 200)) == nil)
    }

    @Test func theFemaleFigureIsNarrowerAtTheShouldersAndWiderAtTheHips() {
        #expect(BodyOutline.female(CGPoint(x: 40, y: 100)).x > 40)
        #expect(BodyOutline.female(CGPoint(x: 60, y: 250)).x < 60)
        #expect(BodyOutline.female(CGPoint(x: 100, y: 250)).x == 100)
    }
}
