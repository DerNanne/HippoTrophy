import CoreGraphics

/// What a sideways drag does to a row of pages laid side by side: how far the
/// row follows the finger, and which page it settles on when the finger lifts.
struct PageSwipe {
    /// How much of the drag the row follows past the first or last page,
    /// where there is nothing left to turn to.
    static var edgeResistance: CGFloat { 1 / 3 }

    let index: Int
    let count: Int
    /// One page and the gap to the next, the distance a turn moves the row.
    let pageWidth: CGFloat

    /// How far the row is moved for a drag of `translation`: all of it towards
    /// a page that exists, a fraction of it towards one that does not.
    func offset(for translation: CGFloat) -> CGFloat {
        let pastTheEnd = (translation > 0 && index == 0) || (translation < 0 && index == count - 1)
        return pastTheEnd ? translation * Self.edgeResistance : translation
    }

    /// How fast, in points a second, a finger has to be moving when it lifts
    /// for a short flick to turn the page.
    static var flickSpeed: CGFloat { 300 }

    /// The page to settle on: the next one past half a page, or for a flick
    /// that way, however short. One swipe turns one page at most, and
    /// dragging back, or a flick against the drag, cancels it.
    func target(translation: CGFloat, velocity: CGFloat) -> Int {
        let flicked = abs(velocity) > Self.flickSpeed
        let direction: CGFloat
        if flicked {
            guard translation * velocity >= 0 else { return index }
            direction = velocity
        } else if abs(translation) > pageWidth / 2 {
            direction = translation
        } else {
            return index
        }
        let turned = direction < 0 ? index + 1 : index - 1
        return min(max(turned, 0), count - 1)
    }
}
