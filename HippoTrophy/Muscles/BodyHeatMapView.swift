import SwiftUI

/// The heat map itself: the figure from the front and from the back, each
/// muscle group shaded by what it got. Tapping a muscle hands its group back.
struct BodyHeatMapView: View {
    let heat: MuscleHeat
    let figure: BodyFigure
    let onSelect: (MuscleGroup) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(BodySide.allCases) { side in
                VStack(spacing: 6) {
                    BodyFigureCanvas(
                        outline: .of(figure, side),
                        heat: heat,
                        onSelect: onSelect
                    )
                    Text(side.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscle heat map")
        .accessibilityValue(spokenSummary)
    }

    /// What the colours say, in words: where most of the training went and
    /// what got none. The list below the map has every number.
    private var spokenSummary: String {
        let hottest = MuscleGroup.allCases.filter { heat.level(for: $0) == QuartileLevel.highest }
        let untrained = MuscleGroup.allCases.filter { heat.sets(for: $0).isEmpty }
        guard !hottest.isEmpty else { return "Nothing trained in this period." }
        var parts = ["Most trained: \(hottest.map(\.displayName).joined(separator: ", "))."]
        if !untrained.isEmpty {
            parts.append("Not trained: \(untrained.map(\.displayName).joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}

/// One figure, drawn in a single canvas. Hit testing asks the outlines rather
/// than the views: some seventy pieces of muscle as views of their own would
/// be a lot of layout for one picture.
private struct BodyFigureCanvas: View {
    let outline: BodyOutline
    let heat: MuscleHeat
    let onSelect: (MuscleGroup) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fit = Fit(in: proxy.size)
            Canvas { context, _ in
                context.concatenate(fit.transform)
                let hair = GraphicsContext.Shading.color(HeatColors.hair)
                let body = GraphicsContext.Shading.color(HeatColors.untrained)

                if let behind = outline.hairBehind {
                    context.fill(Path(behind), with: hair)
                }
                for part in outline.body {
                    context.fill(Path(part), with: body)
                }
                for muscle in outline.muscles {
                    let path = Path(muscle.path)
                    context.fill(path, with: .color(HeatColors.color(forShare: heat.share(for: muscle.group))))
                    // The gaps between the pieces are drawn in the card's
                    // colour, so they read as cuts rather than as lines.
                    context.stroke(
                        path,
                        with: .color(HeatColors.gap),
                        style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)
                    )
                }
                context.fill(Path(outline.hair), with: hair)
            }
            .contentShape(.rect)
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let muscle = outline.muscle(at: fit.outlinePoint(for: value.location)) {
                        onSelect(muscle)
                    }
                }
            )
        }
        .aspectRatio(BodyOutline.size.width / BodyOutline.size.height, contentMode: .fit)
    }

    /// The outline's box scaled into the view, centred.
    private struct Fit {
        let scale: CGFloat
        let offset: CGPoint

        init(in size: CGSize) {
            let box = BodyOutline.size
            scale = min(size.width / box.width, size.height / box.height)
            offset = CGPoint(
                x: (size.width - box.width * scale) / 2,
                y: (size.height - box.height * scale) / 2
            )
        }

        var transform: CGAffineTransform {
            CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        }

        func outlinePoint(for location: CGPoint) -> CGPoint {
            CGPoint(x: (location.x - offset.x) / scale, y: (location.y - offset.y) / scale)
        }
    }
}

/// The heat map's colours, green through yellow, orange and red to purple —
/// `HeatScale` mixes them. The hue carries the meaning, not the lightness, so
/// light and dark mode use the very same colours: purple is the most trained
/// in both.
enum HeatColors {
    static func color(forShare share: Double) -> Color {
        HeatScale.color(forShare: share).map(color) ?? untrained
    }

    /// The whole scale, least trained on the left, for the legend.
    static let gradient = Gradient(stops: HeatScale.stops.map {
        Gradient.Stop(color: color($0.color), location: $0.location)
    })

    private nonisolated static func color(_ rgb: HeatScale.RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static let untrained = Color(.systemGray4)
    static let hair = adaptive(light: 0x3A3A3C, dark: 0x8E8E93)
    /// The colour of the list row the map sits in.
    static let gap = Color(.secondarySystemGroupedBackground)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Less to more, and the grey of a muscle not trained at all.
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            swatch(HeatColors.untrained)
            Text("None")
            Spacer(minLength: 12)
            Text("Less")
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(gradient: HeatColors.gradient, startPoint: .leading, endPoint: .trailing))
                .frame(width: 74, height: 14)
            Text("More")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colours run from grey for not trained, then gradually through green, yellow, orange and red, to purple for the most trained muscle group.")
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 14, height: 14)
    }
}

#Preview {
    BodyHeatMapView(
        heat: MuscleHeat(history: MuscleGroupHistory(entries: [], definitions: []), period: .all),
        figure: .female,
        onSelect: { _ in }
    )
    .padding()
}
