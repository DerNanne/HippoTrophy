import SwiftUI

// MARK: - Blocks

/// The report is built as a list of blocks rather than one long view, because the
/// PDF has to decide where a page ends: a block is the smallest thing that may
/// not be split, which is the `break-inside: avoid` of the design in native form.
struct ReportBlock: Identifiable {
    let id = UUID()
    let content: AnyView

    init<V: View>(@ViewBuilder _ content: () -> V) {
        self.content = AnyView(content())
    }
}

enum WorkoutReportBuilder {
    static func blocks(for data: WorkoutReportData) -> [ReportBlock] {
        var blocks: [ReportBlock] = []
        blocks.append(ReportBlock { ReportHeader() })
        blocks.append(ReportBlock { ReportTitleBlock(data: data) })
        blocks.append(ReportBlock { ReportSummaryCards(data: data) })
        if !data.effortScales.isEmpty {
            blocks.append(ReportBlock { ReportEffortLegend(scales: data.effortScales) })
        }
        if !data.notes.isEmpty {
            blocks.append(ReportBlock { ReportNotesBlock(notes: data.notes) })
        }
        for item in data.items {
            switch item {
            case .exercise(let exercise):
                blocks.append(ReportBlock { ReportExerciseBlock(exercise: exercise) })
            case .superset(let superset):
                blocks.append(ReportBlock { ReportSupersetBlock(superset: superset) })
            }
        }
        return blocks
    }
}

// MARK: - Header

private struct ReportHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image("ReportAppMark")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("HippoTrophy")
                        .font(.system(size: 15, weight: .bold))
                        .kerning(0.3)
                        .foregroundStyle(ReportStyle.textPrimary)
                }
                Spacer()
                Text("WORKOUT REPORT")
                    .font(.system(size: 12))
                    .kerning(0.96)
                    .foregroundStyle(ReportStyle.textSecondary)
            }
            .padding(.bottom, 14)
            Rectangle()
                .fill(ReportStyle.headerRule)
                .frame(height: 2)
        }
        .padding(.bottom, 22)
    }
}

// MARK: - Title

private struct ReportTitleBlock: View {
    let data: WorkoutReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(ReportStyle.textPrimary)
            Text(data.dateText)
                .font(.system(size: 14))
                .foregroundStyle(ReportStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }
}

// MARK: - Summary

private struct ReportSummaryCards: View {
    let data: WorkoutReportData

    var body: some View {
        HStack(spacing: 10) {
            card(value: ReportFormat.count(data.exerciseCount), label: "EXERCISES")
            card(value: ReportFormat.count(data.setCount), label: "SETS")
            card(value: ReportFormat.volume(data.totalVolume, in: data.unit), label: "TOTAL VOLUME")
        }
        .padding(.bottom, 18)
    }

    private func card(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ReportStyle.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .kerning(0.55)
                .foregroundStyle(ReportStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ReportStyle.cardBackground)
        )
    }
}

// MARK: - Effort legend

private struct ReportEffortLegend: View {
    /// The ratings spelt out, so a coach reading the report can tell what the
    /// marks in the set tables mean without having the app. A line per scale
    /// the workout was rated on.
    let scales: [EffortScale]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(scales) { scale in
                HStack(spacing: 14) {
                    Text(scale == .rir ? "EFFORT · REPS IN RESERVE" : "EFFORT")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.55)
                        .foregroundStyle(ReportStyle.textTertiary)
                    switch scale {
                    case .off:
                        EmptyView()
                    case .levels:
                        ForEach(scale.choices, id: \.self) { effort in
                            HStack(spacing: 4) {
                                EffortIndicator(scale: .levels, effort: effort, size: 11)
                                Text(effort.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(ReportStyle.textSecondary)
                            }
                        }
                    case .rir:
                        // The bands, hardest first; 0 is a set to failure.
                        HStack(spacing: 4) {
                            ForEach(RIRBand.allCases, id: \.self) { band in
                                RIRBadge(rir: band.preset, label: band.presetLabel, size: 13)
                            }
                        }
                        Text("0 = failure")
                            .font(.system(size: 11))
                            .foregroundStyle(ReportStyle.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.bottom, ReportStyle.exerciseBlockSpacing)
    }
}

// MARK: - Workout notes

private struct ReportNotesBlock: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WORKOUT NOTES")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.44)
                .foregroundStyle(ReportStyle.textTertiary)
            Text(notes)
                .font(.system(size: 13))
                .foregroundStyle(ReportStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ReportStyle.cardBackground)
        )
        .padding(.bottom, ReportStyle.exerciseBlockSpacing)
    }
}

// MARK: - Page

/// One printed page: the blocks that fit, pushed to the top, with the footer rule
/// pinned to the bottom.
struct ReportPage: View {
    let blocks: [ReportBlock]
    let pageNumber: Int
    let pageCount: Int
    /// Exercises left out of the report. Shown once, above the footer rule
    /// of the last page: it is a caveat about the whole document, and as its own
    /// block it would have claimed a page of its own for a single line.
    let skippedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                block.content
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(
            width: ReportStyle.contentWidth,
            height: ReportStyle.pageSize.height - 2 * ReportStyle.margin,
            alignment: .topLeading
        )
        .padding(ReportStyle.margin)
        .background(ReportStyle.page)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pageNumber == pageCount, skippedCount > 0 {
                Text(skippedNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(ReportStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }
            Rectangle()
                .fill(ReportStyle.divider)
                .frame(height: 1)
                .padding(.bottom, 14)
            HStack {
                Text("Exported from HippoTrophy")
                Spacer()
                if pageCount > 1 {
                    Text("Page \(pageNumber) of \(pageCount)")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(ReportStyle.textTertiary)
        }
        .padding(.top, 30)
    }

    private var skippedNotice: String {
        skippedCount == 1
            ? "1 exercise from this workout logs no weight and reps and is not included in this report."
            : "\(skippedCount) exercises from this workout log no weight and reps and are not included in this report."
    }
}
