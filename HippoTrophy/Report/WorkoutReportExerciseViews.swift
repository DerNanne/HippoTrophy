import SwiftUI

// MARK: - Exercise

struct ReportExerciseBlock: View {
    let exercise: WorkoutReportData.Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportExerciseHeading(exercise: exercise)

            if exercise.mode == .perSide {
                HStack(alignment: .top, spacing: 16) {
                    ReportSetTable(rows: WorkoutReportData.SetRow.numbered(exercise.leftSets), sideLabel: "LEFT", unit: exercise.unit, showsEffort: exercise.showsEffort)
                    ReportSetTable(rows: WorkoutReportData.SetRow.numbered(exercise.rightSets), sideLabel: "RIGHT", unit: exercise.unit, showsEffort: exercise.showsEffort)
                        .padding(.leading, 16)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(ReportStyle.divider)
                                .frame(width: 1)
                        }
                }
            } else {
                ReportSetTable(rows: WorkoutReportData.SetRow.numbered(exercise.sets), sideLabel: nil, unit: exercise.unit, showsEffort: exercise.showsEffort)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, ReportStyle.exerciseBlockSpacing)
    }
}

// MARK: - Superset

/// Both exercises with their own name line and note, then one table of every
/// set in the order they were done. A rule on the leading edge holds the two
/// together; the letters tell the sets apart without relying on colour, which
/// a printout may not have.
struct ReportSupersetBlock: View {
    let superset: WorkoutReportData.Superset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUPERSET")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.44)
                .foregroundStyle(ReportStyle.textTertiary)
            ReportExerciseHeading(exercise: superset.a, member: .a)
            ReportExerciseHeading(exercise: superset.b, member: .b)
            ReportSetTable(rows: superset.rows, sideLabel: nil, unit: superset.a.unit, showsEffort: superset.showsEffort)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ReportStyle.divider)
                .frame(width: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, ReportStyle.exerciseBlockSpacing)
    }
}

// MARK: - Parts

/// An exercise's name line — its letter in a superset, its mode, its volume —
/// and below it what else there is to say: the partner it was trained with
/// when that one is not printed, and its note.
private struct ReportExerciseHeading: View {
    let exercise: WorkoutReportData.Exercise
    var member: SupersetSequence.Member?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let member {
                    ReportMemberMark(member: member)
                }
                Text(exercise.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ReportStyle.textPrimary)
                if exercise.mode != .bilateral {
                    ReportModeBadge(mode: exercise.mode)
                }
                Spacer(minLength: 12)
                if let volumeText = exercise.volumeText {
                    Text(volumeText)
                        .font(.system(size: 12))
                        .foregroundStyle(ReportStyle.textTertiary)
                }
            }

            if let partner = exercise.supersetPartner {
                Text("Superset with \(partner)")
                    .font(.system(size: 12))
                    .foregroundStyle(ReportStyle.textTertiary)
            }

            if !exercise.instructions.isEmpty {
                Text(exercise.instructions)
                    .font(.system(size: 13))
                    .foregroundStyle(ReportStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(ReportStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A superset member's letter, as it heads the exercise and its sets: grey
/// for A, accent for B, as the editor marks them.
private struct ReportMemberMark: View {
    let member: SupersetSequence.Member

    var body: some View {
        Text(member.letter)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(member.reportColor)
            .frame(width: 18, height: 18)
            .background(Circle().fill(member.reportColor.opacity(0.12)))
    }
}

private extension SupersetSequence.Member {
    var reportColor: Color {
        switch self {
        case .a: ReportStyle.textSecondary
        case .b: ReportStyle.accent
        }
    }
}

/// The report's own take on `UnilateralModeBadge` — same words, print colours.
private struct ReportModeBadge: View {
    let mode: UnilateralMode

    var body: some View {
        Text(mode.shortTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ReportStyle.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(ReportStyle.accent.opacity(0.12)))
    }
}

private struct ReportSetTable: View {
    let rows: [WorkoutReportData.SetRow]
    /// "LEFT"/"RIGHT" for an L/R log, nil for a single table.
    let sideLabel: String?
    let unit: WeightUnit
    let showsEffort: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sideLabel {
                Text(sideLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ReportStyle.textSecondary)
            }

            HStack(spacing: 8) {
                columnHeader("SET", alignment: .leading)
                columnHeader("WEIGHT", alignment: .leading)
                columnHeader("REPS", alignment: .leading)
                // Without effort the column stays as blank space, so the
                // tables of all exercises keep their columns in line.
                columnHeader("EFFORT", alignment: .trailing)
                    .opacity(showsEffort ? 1 : 0)
            }

            if rows.isEmpty {
                Text("No sets logged")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(ReportStyle.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(rows) { row in
                    let set = row.set
                    HStack(spacing: 8) {
                        cell(Text(row.label)
                            .foregroundStyle(row.member?.reportColor ?? ReportStyle.textPrimary), alignment: .leading)
                        cell(Text(ReportFormat.load(of: set, in: unit))
                            .foregroundStyle(ReportStyle.textSecondary), alignment: .leading)
                        cell(Text("x\(set.reps)")
                            .fontWeight(.semibold)
                            .foregroundStyle(ReportStyle.textPrimary), alignment: .leading)
                        // An unrated set leaves its cell empty; the gauge
                        // still takes its place so the columns stay put.
                        cell(
                            EffortIndicator(scale: set.effort?.scale ?? .levels, effort: set.effort, size: 13)
                                .opacity(showsEffort && set.effort != nil ? 1 : 0),
                            alignment: .trailing
                        )
                    }
                    .font(.system(size: 14))
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columnHeader(_ title: String, alignment: Alignment) -> some View {
        cell(
            Text(title)
                .font(.system(size: 11))
                .kerning(0.44)
                .foregroundStyle(ReportStyle.textTertiary),
            alignment: alignment
        )
    }

    private func cell(_ content: some View, alignment: Alignment) -> some View {
        content.frame(maxWidth: .infinity, alignment: alignment)
    }
}
