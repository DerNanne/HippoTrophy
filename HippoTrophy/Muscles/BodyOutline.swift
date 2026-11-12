import CoreGraphics
import Foundation

/// Which figure the heat map is drawn on. Only the drawing follows it: the
/// muscles, the counting and the colours are the same for both.
nonisolated enum BodyFigure: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var name: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

nonisolated enum BodySide: CaseIterable, Identifiable {
    case front
    case back

    var id: Self { self }

    var name: String {
        switch self {
        case .front: return "Front"
        case .back: return "Back"
        }
    }
}

/// A figure, front or back, as outlines in a box of `size`: the grey body,
/// the hair, and one outline per piece of muscle, each filed under the muscle
/// group it colours in.
///
/// Drawn from one set of outlines. Every muscle is drawn for one half and
/// mirrored for the other; the female figure is the male one made narrower
/// at the shoulders and waist and wider at the hips, with her own hair. So a
/// change to a muscle's shape is made once and shows on all four figures.
///
/// The muscle groups are the coarse ones the exercises are filed under. Traps
/// is the upper trapezius, between the neck and the shoulders, which shrugs
/// train; the trapezius below it is Back with the lats and the lower back,
/// since rows train it rather than shrugs.
struct BodyOutline {
    struct Muscle {
        let group: MuscleGroup
        let path: CGPath
    }

    nonisolated static let size = CGSize(width: 200, height: 440)

    /// Drawn before the body.
    let hairBehind: CGPath?
    let body: [CGPath]
    let muscles: [Muscle]
    /// Drawn over everything.
    let hair: CGPath

    static func of(_ figure: BodyFigure, _ side: BodySide) -> BodyOutline {
        if let known = cache[Key(figure: figure, side: side)] { return known }
        let outline = BodyOutline(figure: figure, side: side)
        cache[Key(figure: figure, side: side)] = outline
        return outline
    }

    private struct Key: Hashable {
        let figure: BodyFigure
        let side: BodySide
    }

    /// Parsed once per figure: the outlines never change while the app runs.
    private static var cache: [Key: BodyOutline] = [:]

    private init(figure: BodyFigure, side: BodySide) {
        let shape: (CGPoint) -> CGPoint
        if figure == .female {
            shape = { Self.female($0) }
        } else {
            shape = { $0 }
        }
        let mirrored: (CGPoint) -> CGPoint = { shape(CGPoint(x: Self.size.width - $0.x, y: $0.y)) }

        func both(_ data: String) -> [CGPath] {
            [OutlinePath.parse(data, transform: shape), OutlinePath.parse(data, transform: mirrored)]
        }

        body = OutlineData.silhouette.flatMap(both)
            + OutlineData.centred.map { OutlinePath.parse($0, transform: shape) }
        muscles = (side == .front ? OutlineData.front : OutlineData.back).flatMap { group, data in
            both(data).map { Muscle(group: group, path: $0) }
        }

        switch (figure, side) {
        case (.male, .front):
            hair = OutlinePath.parse(OutlineData.maleHairFront, transform: shape)
            hairBehind = nil
        case (.male, .back):
            hair = OutlinePath.parse(OutlineData.maleHairBack, transform: shape)
            hairBehind = nil
        case (.female, .front):
            hair = OutlinePath.parse(OutlineData.femaleHairFront, transform: shape)
            hairBehind = OutlinePath.parse(OutlineData.femaleHairBehind, transform: shape)
        case (.female, .back):
            hair = OutlinePath.parse(OutlineData.femaleHairBack, transform: shape)
            hairBehind = nil
        }
    }

    /// The muscle group under a point in the outline's own box, or nothing
    /// where the point is on bare body, hair or beside the figure. Later
    /// outlines lie over earlier ones, so they are asked first.
    ///
    /// A finger is wider than the cuts between the pieces, so a point in a
    /// cut — down the middle between the two halves, say — takes the muscle
    /// right beside it.
    func muscle(at point: CGPoint) -> MuscleGroup? {
        let reach: CGFloat = 4
        let probes = [CGPoint.zero]
            + (0..<8).map { step in
                let angle = CGFloat(step) * .pi / 4
                return CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
            }
        for offset in probes {
            let probe = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            if let hit = muscles.last(where: { $0.path.contains(probe) }) {
                return hit.group
            }
        }
        return nil
    }

    /// Moves a point of the male figure to where the female figure has it:
    /// towards or away from the middle by the width factor at its height.
    nonisolated static func female(_ point: CGPoint) -> CGPoint {
        let middle = size.width / 2
        return CGPoint(x: middle + (point.x - middle) * femaleWidth(at: point.y), y: point.y)
    }

    nonisolated static func femaleWidth(at y: CGFloat) -> CGFloat {
        let knots = OutlineData.femaleWidth
        guard let first = knots.first, let last = knots.last else { return 1 }
        guard y > first.y else { return first.factor }
        for (lower, upper) in zip(knots, knots.dropFirst()) where y <= upper.y {
            let t = (y - lower.y) / (upper.y - lower.y)
            let eased = t * t * (3 - 2 * t)
            return lower.factor + (upper.factor - lower.factor) * eased
        }
        return last.factor
    }
}

/// The outlines, in a 200 × 440 box, figure facing the viewer. The muscle
/// halves are the left half as seen, x up to 100.
private nonisolated enum OutlineData {
    /// Head, neck, arms, torso and legs: the grey everything else sits on.
    /// One half of the body, mirrored.
    static let silhouette: [String] = [
        "M100,82 L86,82 C72,86 58,88 50,94 C42,100 40,112 44,124 L64,140 C66,165 68,190 70,208 C70,222 64,232 62,246 L100,262 Z",
        "M50,100 C38,108 34,130 34,150 C33,170 34,182 36,196 L59,196 C61,178 63,160 65,138 Z",
        "M36,190 L59,190 C59,215 55,240 51,258 L36,258 C31,240 30,215 36,190 Z",
        "M36,255 L51,255 C55,268 53,285 47,299 C41,302 33,297 31,287 C29,276 31,264 36,255 Z",
        "M61,238 C57,280 63,320 69,348 L96,348 C97,320 99,290 100,262 L100,248 Z",
        "M69,342 L96,342 C97,370 94,395 92,418 L79,418 C72,395 66,370 69,342 Z",
        "M78,412 L93,412 C95,421 96,429 95,436 L70,436 C68,429 72,420 78,412 Z"
    ]

    /// Neck and head, drawn once across the middle.
    static let centred: [String] = [
        "M89,54 L111,54 L114,86 L86,86 Z",
        "M100,9 C112,9 121,20 121,36 C121,52 112,63 100,63 C88,63 79,52 79,36 C79,20 88,9 100,9 Z"
    ]

    /// One half; the other is its mirror image.
    static let front: [(MuscleGroup, String)] = [
        (.shoulders, "M70,93 C60,92 48,96 43,106 C39,116 41,128 49,137 C53,124 60,110 72,101 Z"),
        (.chest, "M98.5,93 L75,93 C67,97 63,108 64,121 C66,134 76,141 88,141 C94,141 97,139 98.5,137 Z"),
        (.traps, "M88,80 C80,86 70,89 62,91 L72,93 C80,90 86,87 90,84 Z"),
        (.biceps, "M50,141 C43,153 41,170 44,186 C48,190 54,190 57,186 C60,170 61,153 57,140 Z"),
        (.forearms, "M38,198 C34,214 36,236 40,252 L49,252 C53,236 57,214 57,198 C51,194 43,194 38,198 Z"),
        (.core, "M85,147 Q85,145 87,145 L97,145 Q98.5,145 98.5,147 L98.5,168 L85,170 Z"),
        (.core, "M85,173 L98.5,171 L98.5,194 L85,195 Z"),
        (.core, "M85,198 L98.5,197 L98.5,220 L85,221 Z"),
        (.core, "M85,224 L98.5,223 L98.5,258 C92,252 86,242 85,224 Z"),
        (.core, "M81,146 C75,160 72,190 72,212 C74,222 78,230 82,236 C83,206 83,176 82,146 Z"),
        (.abductors, "M63,244 C60,258 60,272 62,288 C66,274 70,262 75,252 Z"),
        (.quads, "M67,258 C61,282 63,314 71,338 L78,336 C76,310 76,284 79,262 Z"),
        (.quads, "M81,261 C79,285 80,312 82,338 C86,342 89,340 91,336 C92,310 91,282 89,266 Z"),
        (.adductors, "M91.5,264 L99,268 C98.5,286 97,300 95.5,314 C93.5,296 92.5,278 91.5,264 Z"),
        (.calves, "M70,356 C66,372 68,392 77,410 C79,396 79,376 77,356 Z"),
        (.calves, "M90,356 C94,372 93,392 91,404 C89,390 88,372 88,356 Z")
    ]

    static let back: [(MuscleGroup, String)] = [
        // The trapezius in two: the upper part to the shoulder line, the rest
        // down to the middle of the back. One outline cut at a point on its
        // edge, so the two meet without a step.
        (.traps, "M99,70 L92,73 C85,83 72,89 60,93 C63.6,94.8 67.4,97.2 71.2,100.5 L99,106 Z"),
        (.back, "M99,106 L71.2,100.5 C80,108.2 88.7,120.4 95,140 L99,162 Z"),
        (.shoulders, "M58,96 C47,100 41,112 43,126 C46,132 52,134 56,130 C58,118 62,107 67,100 Z"),
        (.back, "M68,101 C77,104 86,113 92,128 C84,128 74,124 66,114 Z"),
        (.back, "M64,118 C67,142 73,170 83,196 C89,190 95,181 98,173 L97,166 C89,150 77,131 64,118 Z"),
        (.back, "M90,180 C94,178 97,177 99,176 L99,232 C94,230 90,222 88,210 C88,198 89,188 90,180 Z"),
        (.triceps, "M45,135 C40,151 40,170 44,187 L58,187 C61,170 61,151 59,135 Z"),
        (.forearms, "M38,198 C34,214 36,236 40,252 L49,252 C53,236 57,214 57,198 C51,194 43,194 38,198 Z"),
        (.abductors, "M64,227 C71,222 81,222 88,228 C80,234 71,240 62,247 Z"),
        (.glutes, "M66,241 C62,257 64,277 74,287 C84,293 94,291 99,285 L99,237 C90,231 76,233 66,241 Z"),
        (.hamstrings, "M66,293 C64,313 68,331 74,345 L81,343 C79,323 79,307 79,293 Z"),
        (.hamstrings, "M82,293 C81,311 83,331 85,343 L92,341 C94,323 93,307 91,293 Z"),
        (.adductors, "M93.5,293 L99,291 C99,307 98,319 96,327 C95,315 94,303 93.5,293 Z"),
        (.calves, "M70,355 C64,371 68,391 78,403 L84,399 C84,383 84,367 83,355 Z"),
        (.calves, "M85,355 C86,369 87,385 87,399 L90,401 C96,389 96,369 92,355 Z")
    ]

    static let maleHairFront = "M79,36 C77,18 87,7 100,7 C113,7 123,18 121,36 C119,28 117,23 114,21 C106,25 94,25 86,21 C83,23 81,28 79,36 Z"
    static let maleHairBack = "M79,36 C77,18 87,7 100,7 C113,7 123,18 121,36 C121,46 118,54 113,58 C104,61 96,61 87,58 C82,54 79,46 79,36 Z"
    static let femaleHairFront = "M79,40 C77,18 87,6 100,6 C113,6 123,18 121,40 C118,30 112,22 104,20 C96,24 86,28 79,40 Z"
    static let femaleHairBack = "M78,38 C76,16 87,5 100,5 C113,5 124,16 122,38 C122,50 118,58 112,62 C108,64 104,66 104,70 C106,84 106,98 100,112 C94,98 94,84 96,70 C96,66 92,64 88,62 C82,58 78,50 78,38 Z"
    /// Long hair seen from the front falls behind the neck and shoulders, so it
    /// is drawn before the body rather than over it.
    static let femaleHairBehind = "M76,40 C74,16 86,4 100,4 C114,4 126,16 124,40 C124,62 126,80 130,92 C120,96 112,92 108,86 L92,86 C88,92 80,96 70,92 C74,80 76,62 76,40 Z"

    /// How much narrower or wider the female figure is than the male one at a
    /// height: narrower shoulders and waist, wider hips. Between two heights
    /// the factor eases rather than steps, so the outline stays smooth.
    static let femaleWidth: [(y: CGFloat, factor: CGFloat)] = [
        (0, 0.93),
        (70, 0.93),
        (95, 0.86),
        (205, 0.85),
        (250, 1.05),
        (300, 1.0),
        (350, 0.94),
        (440, 0.92)
    ]
}
