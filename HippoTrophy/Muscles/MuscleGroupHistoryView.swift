import SwiftUI
import SwiftData
import Charts

/// One muscle group's history: the sets it got week by week, then every
/// workout that trained it, newest first, with what each exercise did there.
///
/// An exercise is a line rather than its full list of sets — a workout can
/// train the chest with four exercises, and their sets one under another would
/// bury the dates. The line opens the exercise's own history, which has them
/// all.
struct MuscleGroupHistoryView: View {
    let muscle: MuscleGroup

    @Query private var loggedExercises: [ExerciseEntry]
    @Query private var definitions: [ExerciseDefinition]
    @AppStorage(SettingsKey.weightUnit) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @State private var historyEntry: ExerciseEntry?

    /// Twelve weeks is a training block or two: long enough to see a trend,
    /// short enough for the bars to stay readable on a phone.
    private static let weeksShown = 12

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kilograms
    }

    var body: some View {
        let history = MuscleGroupHistory(entries: loggedExercises, definitions: definitions)
        let workouts = history.workouts(training: muscle)

        Group {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Workouts with an exercise filed under \(muscle.displayName) show up here once they are saved.")
                )
            } else {
                List {
                    Section {
                        WeeklySetsChart(weeks: history.weeks(training: muscle, count: Self.weeksShown))
                    } header: {
                        Text("Sets per Week")
                    } footer: {
                        Text("The last twelve weeks, this one so far.")
                    }

                    ForEach(workouts) { workout in
                        Section {
                            ForEach(workout.entries) { entry in
                                entryRow(entry, in: history)
                            }
                        } header: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(header(for: workout.session))
                                Spacer(minLength: 8)
                                MuscleSetsText(sets: workout.sets)
                            }
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(muscle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $historyEntry) { entry in
            ExerciseHistoryView(exerciseName: entry.name, identity: entry.identity, currentSessionID: nil)
        }
    }

    private func entryRow(_ entry: ExerciseEntry, in history: MuscleGroupHistory) -> some View {
        let performance = LastPerformance(entry: entry)
        let note = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // The other muscles say why an exercise is here at all — a deadlift
        // under Glutes is no surprise once Back and Hamstrings stand beside it.
        // Where this muscle only helps, the line says so: its sets count half.
        let targets = history.targets(of: entry)
        let isSecondary = !targets.primary.contains(muscle)
        let others = (isSecondary ? targets.primary : targets.all).filter { $0 != muscle }

        return Button {
            historyEntry = entry
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .foregroundStyle(.primary)
                    if let performance {
                        Text(Self.unbroken(performance.performance(unit: weightUnit), unit: weightUnit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(performance.spokenPerformance(unit: weightUnit))
                    } else if note.isEmpty {
                        Text("Nothing logged")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    if !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    if isSecondary {
                        Text("Secondary here" + (others.isEmpty ? "" : " · mainly " + others.map(\.displayName).joined(separator: " · ")))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else if !others.isEmpty {
                        Text("Also " + others.map(\.displayName).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(Color.blue)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the history of \(entry.name)")
    }

    /// Keeps `3×8 @ 60 kg` on one line when the row wraps, so a line breaks
    /// between sets rather than between a weight and its unit.
    private static func unbroken(_ text: String, unit: WeightUnit) -> String {
        text
            .replacingOccurrences(of: " @ ", with: "\u{00A0}@\u{00A0}")
            .replacingOccurrences(of: " \(unit.symbol)", with: "\u{00A0}\(unit.symbol)")
    }

    private func header(for session: WorkoutSession) -> String {
        let date = session.date.formatted(date: .abbreviated, time: .omitted)
        let name = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? date : "\(date) • \(name)"
    }
}

/// Sets per week as bars, the current week last.
///
/// The weeks are categories rather than dates on a time axis: a time axis
/// labels every other week centred under a pair of bars, which reads as if the
/// label belonged to the bar beside it. Here a label stands under its own bar,
/// every third one counted back from this week so the current week has one.
struct WeeklySetsChart: View {
    let weeks: [MuscleGroupHistory.Week]

    private func label(_ week: MuscleGroupHistory.Week) -> String {
        week.start.formatted(.dateTime.day().month(.abbreviated))
    }

    private var labelled: [String] {
        weeks.reversed().enumerated()
            .filter { $0.offset % 3 == 0 }
            .map { label($0.element) }
    }

    var body: some View {
        // Main sets at the bottom of a bar, secondary ones stacked on top,
        // lighter — the same two counts the list shows.
        Chart(weeks) { week in
            BarMark(
                x: .value("Week", label(week)),
                y: .value("Sets", week.sets.main)
            )
            .foregroundStyle(by: .value("Kind", "Main"))
            .cornerRadius(3)
            BarMark(
                x: .value("Week", label(week)),
                y: .value("Sets", week.sets.secondary)
            )
            .foregroundStyle(by: .value("Kind", "Secondary"))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(["Main": Color.accentColor, "Secondary": Color.accentColor.opacity(0.35)])
        .chartLegend(weeks.contains { $0.sets.secondary > 0 } ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: labelled) { value in
                // A label may run wider than its bar — the bars beside it
                // carry none — instead of being cut to "Oc…".
                AxisValueLabel {
                    if let text = value.as(String.self) {
                        Text(text).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4))
        }
        .frame(height: 160)
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        MuscleGroupHistoryView(muscle: .chest)
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
