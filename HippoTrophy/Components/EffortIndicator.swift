import SwiftUI

/// A set's rating as its scale draws it: the three-bar gauge for easy, normal
/// and hard, a coloured number for reps in reserve. Unrated, it shows the
/// scale's empty form, so it can be tapped to rate; an entry that rates
/// nothing shows nothing.
struct EffortIndicator: View {
    let scale: EffortScale
    let effort: SetEffort?
    var size: CGFloat = 17

    var body: some View {
        switch scale {
        case .off:
            EmptyView()
        case .levels:
            EffortGaugeIcon(level: level, size: size)
        case .rir:
            RIRBadge(rir: rir, size: size)
        }
    }

    private var level: EffortLevel? {
        if case .level(let level) = effort { return level }
        return nil
    }

    private var rir: Double? {
        if case .rir(let rir) = effort { return rir }
        return nil
    }
}

/// Reps in reserve as a number on its band's colour. Unrated, an outline with
/// a dash.
struct RIRBadge: View {
    let rir: Double?
    /// What to print instead of the number — "4+" on the preset button.
    var label: String?

    @ScaledMetric private var height: CGFloat

    init(rir: Double?, label: String? = nil, size: CGFloat = 17) {
        self.rir = rir
        self.label = label
        _height = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
        Text(label ?? rir.map(RIRBand.format) ?? "–")
            .font(.system(size: height * 0.7, weight: .semibold).monospacedDigit())
            .foregroundStyle(rir.map { RIRBand.containing($0).textColor } ?? Color(.tertiaryLabel))
            .padding(.horizontal, height * 0.3)
            .frame(minWidth: height * 1.4, minHeight: height)
            .background {
                if let rir {
                    shape.fill(RIRBand.containing(rir).color)
                } else {
                    shape.strokeBorder(Color(.tertiaryLabel), lineWidth: 1)
                }
            }
            .fixedSize()
            .accessibilityElement()
            .accessibilityLabel("Effort")
            .accessibilityValue(rir.map { "\(RIRBand.format($0)) reps in reserve" } ?? "Not rated")
    }
}

extension RIRBand {
    /// From purple at failure, past red, to green; the band beyond takes the
    /// app's blue — easy, not a warning of anything.
    var color: Color {
        switch self {
        case .failure: return Color(.systemPurple)
        case .halfRep: return Color(.systemRed)
        case .oneRep: return Color(.systemOrange)
        case .twoReps: return Color(.systemYellow)
        case .threeReps: return Color(.systemGreen)
        case .fourOrMore: return Color(.systemBlue)
        }
    }

    /// Dark on the light colours, white on the deep ones, so the number stays
    /// readable on every band.
    var textColor: Color {
        switch self {
        case .oneRep, .twoReps, .threeReps: return .black.opacity(0.8)
        case .failure, .halfRep, .fourOrMore: return .white
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(EffortScale.allCases) { scale in
            HStack(spacing: 10) {
                EffortIndicator(scale: scale, effort: nil)
                ForEach(scale.choices, id: \.self) { effort in
                    EffortIndicator(scale: scale, effort: effort)
                }
            }
        }
        RIRBadge(rir: 2.5)
        RIRBadge(rir: 10)
    }
    .padding()
}
