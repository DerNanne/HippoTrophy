import CoreGraphics
import Foundation

/// Which part of a photo a tile shows: the point it is centred on and how far
/// it is zoomed in. The photo itself stays whole; the full view shows all of
/// it.
///
/// A centre and a zoom rather than a rectangle, because one photo fills frames
/// of different shapes — a machine's square tile and its wider preview — and
/// each shows the same spot. The centre is where the user put it; a frame
/// that cannot be centred there without showing past the edge shows the
/// nearest part that fits.
nonisolated struct PhotoFraming: Hashable, Codable {
    /// Middle of the photo, as a tile showed it before there was framing.
    static let centered = PhotoFraming(x: 0.5, y: 0.5, zoom: 1)
    static let maxZoom = 4.0

    /// The centre, as a fraction of the photo's width and height from its
    /// top left.
    var x: Double
    var y: Double
    /// 1 fills the frame with as much of the photo as fits; 2 shows half as
    /// wide a part.
    var zoom: Double

    var isCentered: Bool { self == .centered }

    /// The part of a photo `imageAspect` wide (width over height) that a frame
    /// `frameAspect` wide shows, as fractions of the photo: never past its
    /// edges, never smaller than `maxZoom` allows.
    func visibleRect(imageAspect: Double, frameAspect: Double) -> CGRect {
        let zoom = min(max(zoom, 1), Self.maxZoom)
        // At zoom 1 the frame is filled: the photo's full height when it is
        // wider than the frame, its full width otherwise.
        var width = 1.0, height = 1.0
        if imageAspect > frameAspect {
            width = frameAspect / imageAspect
        } else {
            height = imageAspect / frameAspect
        }
        width /= zoom
        height /= zoom
        let minX = min(max(x - width / 2, 0), 1 - width)
        let minY = min(max(y - height / 2, 0), 1 - height)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Moved the way a finger drags the photo: `dx` and `dy` are fractions of
    /// the frame, and dragging right brings more of the left into view. Kept
    /// where the frame can show it.
    func panned(dx: Double, dy: Double, imageAspect: Double, frameAspect: Double) -> PhotoFraming {
        let rect = visibleRect(imageAspect: imageAspect, frameAspect: frameAspect)
        var moved = PhotoFraming(x: rect.midX - dx * rect.width, y: rect.midY - dy * rect.height, zoom: zoom)
        moved.clamp(imageAspect: imageAspect, frameAspect: frameAspect)
        return moved
    }

    /// Zoomed by `factor` about the current centre, between 1 and `maxZoom`.
    func zoomed(by factor: Double, imageAspect: Double, frameAspect: Double) -> PhotoFraming {
        var zoomed = self
        zoomed.zoom = min(max(zoom * factor, 1), Self.maxZoom)
        zoomed.clamp(imageAspect: imageAspect, frameAspect: frameAspect)
        return zoomed
    }

    /// The centre the frame actually shows, so that a drag starts from what
    /// is on screen rather than from a spot past the edge.
    private mutating func clamp(imageAspect: Double, frameAspect: Double) {
        let rect = visibleRect(imageAspect: imageAspect, frameAspect: frameAspect)
        x = rect.midX
        y = rect.midY
        zoom = min(max(zoom, 1), Self.maxZoom)
    }
}

/// A photo as an editor holds it before it is saved: the prepared picture
/// and the part of it a tile shows.
nonisolated struct PhotoDraft: Equatable {
    var data: Data
    var framing: PhotoFraming = .centered
}
