import SwiftUI
import SwiftData

struct ExerciseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The title; what is shown is everything logged as `identity`.
    let exerciseName: String
    let identity: ExerciseIdentity
    let currentSessionID: UUID?

    @Query private var definitions: [ExerciseDefinition]
    @State private var pastEntries: [ExerciseEntry] = []
    @State private var progress = ExerciseProgress(sessions: [])
    /// Off on every open on purpose: halving is right for a machine or a barbell
    /// and wrong for dumbbells, and that is a judgement per exercise. A setting
    /// that stuck around would quietly mis-scale the next exercise looked at.
    @State private var showPerSide = false
    @AppStorage(SettingsKey.weightUnit) private var weightUnitRaw = WeightUnit.kilograms.rawValue

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kilograms
    }

    var body: some View {
        NavigationStack {
            Group {
                if pastEntries.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("What you log for this exercise — or a note on it — shows up here once the workout is saved.")
                    )
                } else {
                    List {
                        PersonalRecordSection(records: progress.records, unit: weightUnit)
                        ExerciseProgressSection(progress: progress, unit: weightUnit)

                        ForEach(pastEntries) { entry in
                            let mode = entry.unilateralMode
                            Section {
                                // The note is part of what was logged: for a
                                // warm-up or a skipped exercise it is all there is.
                                // The instructions say how it was meant.
                                EntryTextsView(entry: entry, showsGym: true)
                                // Only what was trained: a set planned and not
                                // done belongs to its workout's page, not here.
                                let groups = SetGroup.groups(of: entry, doneOnly: true)
                                let layout = SetValuesLayout(
                                    sets: groups.flatMap(\.sets),
                                    tracksSets: entry.tracksSets(among: definitions)
                                )
                                if !entry.hasLoggedData {
                                    Text("Nothing logged")
                                        .foregroundStyle(.tertiary)
                                } else if groups.contains(where: { !$0.sets.isEmpty }) {
                                    SetValuesBlock(
                                        layout: layout,
                                        groups: groups,
                                        unit: weightUnit,
                                        effortScale: entry.effortScale,
                                        showsNumber: entry.sets.count > 1,
                                        weightText: { weightText($0, mode: mode) },
                                        recordSetIDs: recordSetIDs
                                    )
                                    .listRowInsets(.vertical, 0)
                                }
                            } header: {
                                HStack {
                                    Text(sessionHeader(for: entry))
                                    if mode != .bilateral {
                                        UnilateralModeBadge(mode: mode)
                                    }
                                    if entry.assistance.isAssisted {
                                        AssistanceBadge(assistance: entry.assistance)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .textCase(nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only worth offering once there is something to line up: a
                // two-sided entry next to a one-sided one.
                if canCompareSides {
                    ToolbarItem(placement: .topBarLeading) {
                        Toggle(isOn: $showPerSide) {
                            Text("Per Side")
                        }
                        .toggleStyle(.button)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadHistory)
        }
    }

    private var recordSetIDs: Set<UUID> {
        Set(progress.records.compactMap(\.set.setID))
    }

    private var canCompareSides: Bool {
        let modes = Set(pastEntries.filter(\.logsWeightAndReps).map(\.unilateralMode))
        return modes.contains(.bilateral) && modes.count > 1
    }

    /// The logged weight stays the number on the row, always. A two-sided entry
    /// picks up what one side moved in brackets, since its weight is shared
    /// between the sides. A one-sided entry is left exactly as it is: its weight
    /// is already per side, so there is nothing to add but noise — `nil`, and
    /// the row prints the weight as it always does.
    private func weightText(_ set: SetEntry, mode: UnilateralMode) -> String? {
        guard showPerSide, !mode.logsPerSideWeight else { return nil }
        let kilograms = set.weightKg ?? 0
        let perSide = weightUnit.number(fromKilograms: kilograms / 2)
        return "\(weightUnit.formatted(kilograms: kilograms)) (\(perSide)/side)"
    }

    private func sessionHeader(for entry: ExerciseEntry) -> String {
        guard let session = entry.session else { return "Unknown date" }
        let date = session.date.formatted(date: .abbreviated, time: .shortened)
        let name = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? date : "\(date) • \(name)"
    }

    /// Exercises are matched by identity — a catalog exercise by its key, an
    /// own one by name — see `ExerciseHistory`.
    private func loadHistory() {
        pastEntries = ExerciseHistory.fetch(in: modelContext, excludingSession: currentSessionID)
            .entries(of: identity)
        progress = ExerciseProgress(entries: pastEntries)
    }
}
