import SwiftUI
import Charts

/// The top of an exercise's history: one point per workout on a time axis, in
/// the number last picked. Touching the graph shows a workout's value and the
/// set it comes from.
///
/// Which numbers there are and where the points go is `ExerciseProgress`'s to
/// decide; this only draws them. Nothing shows for a history without a single
/// set of weight training.
struct ExerciseProgressSection: View {
    let progress: ExerciseProgress
    let unit: WeightUnit

    @AppStorage(SettingsKey.progressMetric) private var preferredRaw = ProgressMetric.estimatedMax.rawValue

    private var preferred: ProgressMetric {
        ProgressMetric(rawValue: preferredRaw) ?? .estimatedMax
    }

    var body: some View {
        if let metric = progress.metric(preferring: preferred) {
            Section {
                ExerciseProgressChart(points: progress.points(for: metric), metric: metric, unit: unit)
            } header: {
                header(showing: metric)
            } footer: {
                Text(metric.explanation(countingAssistance: progress.countsAssistance))
            }
        }
    }

    private func header(showing metric: ProgressMetric) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Progress")
            Spacer(minLength: 8)
            if progress.metrics.count > 1 {
                // Picking stores the choice for every exercise; one that cannot
                // show it falls back on its own and leaves the choice alone.
                Menu {
                    Picker("Show", selection: Binding(
                        get: { metric },
                        set: { preferredRaw = $0.rawValue }
                    )) {
                        ForEach(progress.metrics) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(metric.title)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                }
                // Inside a section header a menu would otherwise inherit the
                // uppercasing and muted colour and stop reading as a control.
                .textCase(nil)
                // A new menu per metric: the old one kept the width of the
                // title before, and a longer one came out as "lax Weight".
                .id(metric)
            } else {
                Text(metric.title)
            }
        }
        .textCase(nil)
    }
}

/// The graph itself, under a line that names the newest workout or the one
/// tapped. An L/R log draws a left and a right line; everything else is one
/// line. A point's shape says whether its weight is shared by both sides or
/// one side's, so a switch between the two shows without being converted.
///
/// A tap selects and the selection stays: a selection that lasts only while
/// the finger is down cannot be read under the finger.
struct ExerciseProgressChart: View {
    let points: [ExerciseProgress.Point]
    let metric: ProgressMetric
    let unit: WeightUnit

    @State private var selectedDate: Date?

    private var selected: [ExerciseProgress.Point] {
        guard let selectedDate else { return [] }
        return ExerciseProgress.points(nearest: selectedDate, in: points)
    }

    /// What the line above the graph speaks of: the workout touched, and the
    /// newest one while nothing is.
    private var shown: [ExerciseProgress.Point] {
        guard selected.isEmpty, let newest = points.last else { return selected }
        return ExerciseProgress.points(nearest: newest.date, in: points)
    }

    private var hasSeveralLines: Bool {
        Set(points.map(\.line)).count > 1
    }

    /// The lines the points fall on, in a fixed order.
    private var lines: [SetSide] {
        let present = Set(points.map(\.line))
        return [SetSide.both, .left, .right].filter(present.contains)
    }

    private var hasSeveralShapes: Bool {
        Set(points.map(\.mode.logsPerSideWeight)).count > 1
    }

    private var plottedValues: [Double] {
        points.map { plotted($0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            detail(for: shown)
            chart
        }
        .padding(.vertical, 8)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value(metric.title, plotted(point.value))
                )
                .foregroundStyle(by: .value("Side", Self.lineName(point.line)))

                // The shape lives on its own mark: given to the line, it would
                // break the line wherever the mode changes. Only a history of
                // both shapes gets one, or the legend names a shape that
                // tells nothing apart.
                if hasSeveralShapes {
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metric.title, plotted(point.value))
                    )
                    .foregroundStyle(by: .value("Side", Self.lineName(point.line)))
                    .symbol(by: .value("Weight", point.mode.logsPerSideWeight ? "Unilateral" : "Bilateral"))
                } else {
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metric.title, plotted(point.value))
                    )
                    .foregroundStyle(by: .value("Side", Self.lineName(point.line)))
                }
            }

            if let first = selected.first {
                RuleMark(x: .value("Date", first.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
        // Only the lines that are there, so an L/R history does not list
        // "Both" in the legend.
        .chartForegroundStyleScale(domain: lines.map(Self.lineName), range: lines.map(Self.lineColor))
        .chartLegend(hasSeveralLines || hasSeveralShapes ? .visible : .hidden)
        .modifier(ProgressAxes(
            values: ExerciseProgress.valueDomain(of: plottedValues),
            dates: ExerciseProgress.dateDomain(of: points.map(\.date))
        ))
        .chartYAxis {
            // Reps come whole; an axis at 9.5 would invent half a rep.
            AxisMarks(
                position: .trailing,
                values: metric.isWeight ? .automatic(desiredCount: 4) : .automatic(minimumStride: 1, desiredCount: 4)
            )
        }
        .chartXAxis {
            // Centred under their mark: left-aligned, a date near the end
            // runs into the value labels and is cut to "Sep…".
            AxisMarks { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(anchor: .top)
            }
        }
        .chartYAxisLabel(metric.isWeight ? unit.symbol : "reps")
        .chartXSelection(value: $selectedDate)
        // A tap rather than the built-in drag, which lets go of the selection
        // with the finger and would fight the list's scrolling.
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { tap in
                proxy.selectXValue(at: tap.location.x)
            }
        }
        .frame(height: 200)
    }

    /// The value on the chart's own scale: weights in the unit shown, reps as
    /// they are.
    private func plotted(_ value: Double) -> Double {
        metric.isWeight ? unit.value(fromKilograms: value) : value
    }

    private func detail(for points: [ExerciseProgress.Point]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let first = points.first {
                Text(first.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ForEach(points) { point in
                HStack(spacing: 4) {
                    if point.line != .both {
                        Text(Self.lineName(point.line) + ":")
                    }
                    Text(metric.text(point.value, unit: unit))
                        .fontWeight(.semibold)
                    if let source = point.sourceText(unit: unit) {
                        Text("· " + source)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        // Room for two sides at all times, so touching an L/R graph does not
        // push it down.
        .frame(minHeight: hasSeveralLines ? 60 : 40, alignment: .topLeading)
    }

    private static func lineColor(_ line: SetSide) -> Color {
        switch line {
        case .both: .accentColor
        case .left: .purple
        case .right: .orange
        }
    }

    private static func lineName(_ line: SetSide) -> String {
        switch line {
        case .both: "Both"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// The axes' bounds where the chart's own would fail — see
/// `ExerciseProgress.valueDomain` and `dateDomain`. Everywhere else the chart
/// picks round bounds itself, and the vertical one need not start at zero:
/// progress is the change, not the distance from nothing.
private struct ProgressAxes: ViewModifier {
    let values: ClosedRange<Double>?
    let dates: ClosedRange<Date>?

    func body(content: Content) -> some View {
        let scaled = Group {
            if let values {
                content.chartYScale(domain: values)
            } else {
                content.chartYScale(domain: .automatic(includesZero: false))
            }
        }
        // Room after the newest workout: without it its point sits on the
        // value labels to the right, and the last date label is cut to "S…".
        let range = PlotDimensionScaleRange.plotDimension(startPadding: 8, endPadding: 24)
        if let dates {
            scaled.chartXScale(domain: dates, range: range)
        } else {
            scaled.chartXScale(range: range)
        }
    }
}
