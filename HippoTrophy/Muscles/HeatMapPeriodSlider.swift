import SwiftUI

/// Picks how far back the heat map looks, as a slider that snaps to its five
/// stops: all of it on the left, the last month on the right. Built rather
/// than taken from `Slider`, so each label can stand exactly under its stop.
struct HeatMapPeriodSlider: View {
    @Binding var period: HeatMapPeriod

    private static let periods = HeatMapPeriod.allCases
    private static let knob: CGFloat = 26
    private static let stop: CGFloat = 6

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 4)
                        .padding(.horizontal, Self.knob / 2)
                    // Filled from the knob to the right end — the stretch of
                    // time that is counted, up to today.
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(width - Self.knob / 2 - x(of: period, in: width), 0), height: 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Self.knob / 2)
                    ForEach(Self.periods) { stop in
                        Circle()
                            .fill(stop.rawValue >= period.rawValue ? Color.accentColor : Color(.systemGray3))
                            .frame(width: Self.stop, height: Self.stop)
                            .position(x: x(of: stop, in: width), y: Self.knob / 2)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .frame(width: Self.knob, height: Self.knob)
                        .position(x: x(of: period, in: width), y: Self.knob / 2)
                }
                .frame(height: Self.knob)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        period = nearest(to: value.location.x, in: width)
                    }
                )
            }
            .frame(height: Self.knob)

            GeometryReader { proxy in
                ForEach(Self.periods) { stop in
                    Text(stop.shortName)
                        .font(.caption.weight(stop == period ? .semibold : .regular))
                        .foregroundStyle(stop == period ? .primary : .secondary)
                        .fixedSize()
                        .position(x: x(of: stop, in: proxy.size.width), y: 8)
                        .onTapGesture { period = stop }
                }
            }
            .frame(height: 16)
        }
        .sensoryFeedback(.selection, trigger: period)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Period")
        .accessibilityValue(period.name)
        .accessibilityAdjustableAction { direction in
            // Swiping up shortens the period, matching the slider's right.
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    /// A stop's centre. The knob's half width is kept free at either end, so
    /// it never leaves the track.
    private func x(of stop: HeatMapPeriod, in width: CGFloat) -> CGFloat {
        let track = max(width - Self.knob, 0)
        let fraction = CGFloat(stop.rawValue) / CGFloat(Self.periods.count - 1)
        return Self.knob / 2 + track * fraction
    }

    private func nearest(to x: CGFloat, in width: CGFloat) -> HeatMapPeriod {
        Self.periods.min { abs(self.x(of: $0, in: width) - x) < abs(self.x(of: $1, in: width) - x) } ?? period
    }

    private func step(by offset: Int) {
        if let next = HeatMapPeriod(rawValue: period.rawValue + offset) {
            period = next
        }
    }
}
