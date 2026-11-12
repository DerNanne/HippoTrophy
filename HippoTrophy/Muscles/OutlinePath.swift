import CoreGraphics

/// Reads the outlines the body figures are drawn from: a small subset of SVG
/// path data — absolute `M`, `L`, `Q`, `C` and `Z`, numbers separated by commas
/// or spaces. That is all the figures use, and keeping it that small keeps a
/// typo from being read as some other command.
///
/// Every point goes through `transform` on the way in, control points
/// included, which is how one half of a figure becomes the other and how the
/// female figure is shaped from the male one.
nonisolated enum OutlinePath {
    static func parse(_ data: String, transform: (CGPoint) -> CGPoint = { $0 }) -> CGPath {
        let path = CGMutablePath()
        var numbers: [CGFloat] = []
        var command: Character?

        func point(_ index: Int) -> CGPoint {
            transform(CGPoint(x: numbers[index], y: numbers[index + 1]))
        }

        // Applies the pending command once its numbers are in.
        func flush() {
            guard let command else { return }
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: point(0))
            case "L" where numbers.count >= 2:
                path.addLine(to: point(0))
            case "Q" where numbers.count >= 4:
                path.addQuadCurve(to: point(2), control: point(0))
            case "C" where numbers.count >= 6:
                path.addCurve(to: point(4), control1: point(0), control2: point(2))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            numbers.removeAll()
        }

        var token = ""
        func endNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        for character in data {
            if "MLQCZ".contains(character) {
                endNumber()
                flush()
                command = character
            } else if character == "," || character == " " {
                endNumber()
            } else {
                token.append(character)
            }
        }
        endNumber()
        flush()
        return path
    }
}
