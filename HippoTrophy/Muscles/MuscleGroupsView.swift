import SwiftUI
import SwiftData

/// Where the training goes: a heat map of the muscle groups over a period,
/// then every muscle group with its sets in that period and when it was last
/// trained — the way into a muscle group's history, the way the chart icon beside
/// an exercise is the way into its own. The map, its legend and the list read
/// one period, so a colour and the number beside it always agree.
struct MuscleGroupsView: View {
    @Query private var loggedExercises: [ExerciseEntry]
    @Query private var definitions: [ExerciseDefinition]
    @AppStorage(SettingsKey.bodyFigure) private var bodyFigureRaw = BodyFigure.male.rawValue
    // The period outlives the screen, like the workout list's: coming back
    // lands on the view last looked at.
    @AppStorage(SettingsKey.heatMapPeriod) private var periodRaw = HeatMapPeriod.month.rawValue
    // Kept like the period. Unset is Strength alone — see `CategoryFilter`.
    @AppStorage(SettingsKey.heatMapCategories) private var categoriesStored = ""
    @State private var selectedMuscle: MuscleGroup?

    private var period: Binding<HeatMapPeriod> {
        Binding(
            get: { HeatMapPeriod(rawValue: periodRaw) ?? .month },
            set: { periodRaw = $0.rawValue }
        )
    }

    private var categoryOptions: [CategoryFilter.Option] { CategoryFilter.options }

    private var categories: CategoryFilter {
        CategoryFilter(stored: categoriesStored, options: categoryOptions)
    }

    var body: some View {
        // Built once: every row asks the same entries. Read from the queries,
        // so a workout saved elsewhere shows without a reload. The filter
        // reaches the map, the list and the unfiled names alike, so a colour
        // and the number beside it still agree; a muscle's own history keeps
        // everything.
        let options = categoryOptions
        let categories = self.categories
        let history = MuscleGroupHistory(entries: loggedExercises, definitions: definitions, categories: categories)
        let unfiled = history.unfiledNames
        let heat = MuscleHeat(history: history, period: period.wrappedValue)

        List {
            Section {
                // Slider, map and legend are one picture; lines between them
                // would cut it into three.
                HeatMapPeriodSlider(period: period)
                    .padding(.top, 4)
                    .listRowSeparator(.hidden)
                BodyHeatMapView(
                    heat: heat,
                    figure: BodyFigure(rawValue: bodyFigureRaw) ?? .male,
                    onSelect: { selectedMuscle = $0 }
                )
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
                HeatLegend()
                    .listRowSeparator(.hidden)
            } header: {
                // On one line while it fits; a long category name moves the
                // date under it rather than wrapping the names mid-list. The
                // date is the smaller part, so the common case — one category
                // with its symbol — still fits beside it.
                let title = Text("\(period.wrappedValue.name) · \(categoryHeading(categories, options: options))")
                    .accessibilityLabel("\(period.wrappedValue.name), \(categories.label(options: options))")
                let since = heat.start.map {
                    Text("since \($0.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .textCase(nil)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title.lineLimit(1)
                        Spacer(minLength: 8)
                        since.lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        since
                    }
                }
            } footer: {
                Text("Shaded against the muscle group that got the most sets in the period. Tap a muscle for its history.")
            }

            Section {
                ForEach(MuscleGroup.allCases) { muscle in
                    NavigationLink {
                        MuscleGroupHistoryView(muscle: muscle)
                    } label: {
                        row(muscle, in: history, heat: heat)
                    }
                }
            } header: {
                HStack {
                    Text("Muscle Group")
                    Spacer(minLength: 8)
                    Text("Sets")
                }
            } footer: {
                Text("A set counts for every muscle group its exercise is filed under: for its main ones as a set, for the ones it only helps as a secondary set, in grey — a set of squats is a set for Quads and Glutes and a secondary one for Adductors. The colour weighs a secondary set as half. Past workouts follow how an exercise is filed today.")
            }

            if !unfiled.isEmpty {
                Section {
                    Label {
                        Text("Not counted, because no muscle group is picked for \(unfiled.count == 1 ? "it" : "them"): \(unfiled.joined(separator: ", ")).")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.subheadline)
                    NavigationLink {
                        ManageExercisesView(opensUnfiled: true)
                    } label: {
                        Text("Exercises Without Muscle Groups")
                    }
                } header: {
                    Text(CountFormat.text(unfiled.count, "Exercise", "Exercises") + " Not Filed")
                }
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                categoryMenu(options: options, picked: categories)
            }
        }
        .navigationDestination(item: $selectedMuscle) { muscle in
            MuscleGroupHistoryView(muscle: muscle)
        }
    }

    /// The categories in the heading, each named one with its symbol in
    /// front, as the menu shows it. A count or "All Categories" goes without:
    /// a row of symbols there would be a second legend to learn.
    private func categoryHeading(_ categories: CategoryFilter, options: [CategoryFilter.Option]) -> Text {
        guard let named = categories.named(options: options) else {
            return Text(categories.label(options: options))
        }
        return named.enumerated().reduce(Text("")) { heading, item in
            let (index, option) = item
            let separator = index == 0 ? "" : ", "
            // Text tints an image it holds in its own colour; a symbol made
            // Text of its own keeps the colour given it.
            let symbol = Text(Image(systemName: CategoryFilter.symbolName(of: option))).foregroundStyle(option?.tint ?? .secondary)
            return Text("\(heading)\(separator)\(symbol) \(CategoryFilter.name(of: option))")
        }
    }

    /// One line per category to tick. The menu stays open, since picking
    /// several is the point; the last one picked cannot be dropped.
    private func categoryMenu(options: [CategoryFilter.Option], picked: CategoryFilter) -> some View {
        Menu {
            Section("Count Exercises In") {
                ForEach(options, id: \.self) { option in
                    Toggle(isOn: Binding(
                        get: { picked.contains(option) },
                        set: { _ in
                            var changed = picked
                            changed.toggle(option)
                            categoriesStored = changed.stored
                        }
                    )) {
                        Label { Text(CategoryFilter.name(of: option)) } icon: { CategoryFilter.icon(of: option) }
                    }
                }
            }
        } label: {
            Label("Categories", systemImage: "line.3.horizontal.decrease")
        }
        .menuActionDismissBehavior(.disabled)
    }

    private func row(_ muscle: MuscleGroup, in history: MuscleGroupHistory, heat: MuscleHeat) -> some View {
        let sets = heat.sets(for: muscle)
        let last = history.lastTrained(muscle)

        return HStack(spacing: 12) {
            // The muscle's colour on the map, so the list doubles as its key.
            Circle()
                .fill(HeatColors.color(forShare: heat.share(for: muscle)))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.displayName)
                Group {
                    if let last {
                        Text("Last trained \(LastPerformance.age(of: last, now: .now))")
                    } else {
                        Text("Not trained yet")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Main sets as the figure, secondary ones beneath in grey.
            VStack(alignment: .trailing, spacing: 2) {
                if sets.main > 0 || sets.secondary == 0 {
                    Text(sets.isEmpty ? "—" : "\(sets.main)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(sets.isEmpty ? .tertiary : .primary)
                }
                if sets.secondary > 0 {
                    Text("+\(sets.secondary) secondary")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(MuscleSetsText.spoken(sets))
    }
}

#Preview {
    NavigationStack {
        MuscleGroupsView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
