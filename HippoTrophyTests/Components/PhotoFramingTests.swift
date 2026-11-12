import CoreGraphics
import Foundation
import Testing
@testable import HippoTrophy

struct PhotoFramingTests {
    private func expect(_ rect: CGRect, _ x: Double, _ y: Double, _ width: Double, _ height: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        let close = { (a: Double, b: Double) in abs(a - b) < 0.0001 }
        #expect(
            close(rect.minX, x) && close(rect.minY, y) && close(rect.width, width) && close(rect.height, height),
            "\(rect)", sourceLocation: sourceLocation
        )
    }

    @Test func centeredShowsTheMiddleAsATileDidBefore() {
        // A 4:3 photo in a square tile: its full height, the middle three quarters of its width.
        expect(PhotoFraming.centered.visibleRect(imageAspect: 4.0 / 3, frameAspect: 1), 0.125, 0, 0.75, 1)
        // A portrait photo in a wide tile: its full width, a band of its height.
        expect(PhotoFraming.centered.visibleRect(imageAspect: 0.5, frameAspect: 1.5), 0, 1.0 / 3, 1, 1.0 / 3)
    }

    @Test func zoomShowsASmallerPartAroundTheCentre() {
        let framing = PhotoFraming(x: 0.5, y: 0.5, zoom: 2)
        expect(framing.visibleRect(imageAspect: 1, frameAspect: 1), 0.25, 0.25, 0.5, 0.5)
    }

    @Test func aCentreNearTheEdgeShowsTheNearestPartThatFits() {
        let framing = PhotoFraming(x: 0.95, y: 0.05, zoom: 2)
        expect(framing.visibleRect(imageAspect: 1, frameAspect: 1), 0.5, 0, 0.5, 0.5)
    }

    /// One framing serves a machine's square tile and its wide preview alike.
    @Test func theSameSpotInFramesOfDifferentShapes() {
        let framing = PhotoFraming(x: 0.4, y: 0.5, zoom: 1)
        let square = framing.visibleRect(imageAspect: 1.5, frameAspect: 1)
        let wide = framing.visibleRect(imageAspect: 1.5, frameAspect: 1.5)
        expect(square, 0.4 - 1.0 / 3, 0, 2.0 / 3, 1)
        expect(wide, 0, 0, 1, 1)
    }

    @Test func zoomStaysBetweenOneAndTheMost() {
        let framing = PhotoFraming.centered
        #expect(framing.zoomed(by: 0.5, imageAspect: 1, frameAspect: 1).zoom == 1)
        #expect(framing.zoomed(by: 10, imageAspect: 1, frameAspect: 1).zoom == PhotoFraming.maxZoom)
        #expect(framing.zoomed(by: 2, imageAspect: 1, frameAspect: 1).zoom == 2)
    }

    @Test func draggingRightBringsTheLeftIntoView() {
        let zoomed = PhotoFraming(x: 0.5, y: 0.5, zoom: 2)
        let dragged = zoomed.panned(dx: 0.5, dy: 0, imageAspect: 1, frameAspect: 1)
        // Half a frame is a quarter of the photo at zoom 2.
        #expect(abs(dragged.x - 0.25) < 0.0001)
        #expect(dragged.y == 0.5)
    }

    @Test func aDragStopsAtTheEdge() {
        let zoomed = PhotoFraming(x: 0.5, y: 0.5, zoom: 2)
        let dragged = zoomed.panned(dx: 5, dy: -5, imageAspect: 1, frameAspect: 1)
        #expect(dragged.x == 0.25 && dragged.y == 0.75)
    }

    /// Without zoom a frame already shows the photo's full height, so there is
    /// nowhere to move up or down.
    @Test func atZoomOneOnlyTheLongSideMoves() {
        let dragged = PhotoFraming.centered.panned(dx: 0.2, dy: 0.2, imageAspect: 2, frameAspect: 1)
        #expect(dragged.y == 0.5)
        #expect(dragged.x < 0.5)
    }
}
