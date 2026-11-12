import Foundation

/// The heat map's colour for a muscle group, from its share of the most
/// trained one: green through yellow, orange and red to purple, without
/// steps. A group with a quarter of the sets and one with half of them are
/// told apart, where four fixed shades would put both in yellow.
///
/// No share at all has no colour here: untrained stays the grey of the body,
/// so a muscle left out looks left out rather than "a little".
nonisolated enum HeatScale {
    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(_ hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        func mixed(with other: RGB, by fraction: Double) -> RGB {
            RGB(
                red: red + (other.red - red) * fraction,
                green: green + (other.green - green) * fraction,
                blue: blue + (other.blue - blue) * fraction
            )
        }
    }

    /// Where each colour sits on the way from the least to the most trained,
    /// evenly spaced: the four colours the map once had in steps, and purple
    /// beyond red for the very top.
    static let stops: [(location: Double, color: RGB)] = [
        (0, RGB(0x34C759)),
        (0.25, RGB(0xFFCC00)),
        (0.5, RGB(0xFF9500)),
        (0.75, RGB(0xFF3B30)),
        (1, RGB(0xAF52DE)),
    ]

    /// The colour for a share of the most trained group, or nothing for a
    /// group not trained at all.
    static func color(forShare share: Double) -> RGB? {
        guard share > 0 else { return nil }
        let share = min(share, 1)
        for (lower, upper) in zip(stops, stops.dropFirst()) where share <= upper.location {
            let fraction = (share - lower.location) / (upper.location - lower.location)
            return lower.color.mixed(with: upper.color, by: fraction)
        }
        return stops[stops.count - 1].color
    }
}
