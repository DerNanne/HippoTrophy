import SwiftUI

/// The three-bar gauge that says how hard a set felt, on the easy, normal,
/// hard scale.
///
/// The bars rise from left to right and the ones up to the level are filled, so
/// the level reads at a glance without counting. Colour carries the state, not
/// the bar position: every filled bar takes the state's own colour, which is
/// what keeps easy and hard apart when the row is only glanced at. A set that
/// was not rated shows the bars empty.
struct EffortGaugeIcon: View {
    let level: EffortLevel?

    /// Point size of the square the gauge is drawn in, before Dynamic Type.
    @ScaledMetric private var side: CGFloat

    /// The design draws into a 16×16 box: three bars 3 wide and 5, 9 and 13
    /// tall, sitting on the bottom edge with 2.5 between them. Everything below
    /// is measured in that box and scaled, so one set of numbers serves every
    /// size the gauge is used at.
    private static let referenceSide: CGFloat = 16
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2.5
    private static let barCornerRadius: CGFloat = 1
    private static let barHeights: [CGFloat] = [5, 9, 13]

    init(level: EffortLevel?, size: CGFloat = 17) {
        self.level = level
        _side = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        let scale = side / Self.referenceSide

        HStack(alignment: .bottom, spacing: Self.barSpacing * scale) {
            ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: Self.barCornerRadius * scale, style: .continuous)
                    .fill(index <= (level?.rawValue ?? -1) ? Self.color(for: level) : Color(.tertiaryLabel))
                    .frame(width: Self.barWidth * scale, height: height * scale)
            }
        }
        .frame(width: side, height: side)
        // The bars mean nothing to VoiceOver on their own, and unlike the emoji
        // they replaced there is no text to fall back on, so the gauge names
        // itself. A row that speaks as one piece overrides this with its own.
        .accessibilityElement()
        .accessibilityLabel("Effort")
        .accessibilityValue(level?.label ?? "Not rated")
    }

    /// Green for easy, the app's own blue for the everyday case, orange for
    /// hard. Orange rather than red: a hard set is often the point of the
    /// session, and red reads as something having gone wrong.
    private static func color(for level: EffortLevel?) -> Color {
        switch level {
        case .easy: return Color(.systemGreen)
        case .normal: return .accentColor
        case .hard: return Color(.systemOrange)
        case nil: return Color(.tertiaryLabel)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(EffortLevel.allCases, id: \.self) { level in
            HStack(spacing: 10) {
                EffortGaugeIcon(level: level)
                Text(level.label)
            }
        }
        HStack(spacing: 10) {
            EffortGaugeIcon(level: nil)
            Text("Not rated")
        }
    }
    .padding()
}
