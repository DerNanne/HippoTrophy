import SwiftUI
import SwiftData

/// Keys for user preferences stored in `UserDefaults`, so the settings screen and
/// the views that honour a preference cannot drift apart on a spelling.
nonisolated enum SettingsKey {
    static let collapseOtherExercises = "collapseOtherExercises"
    /// Whether the editor shows the last logged sets under an exercise's name.
    static let showLastPerformance = "showLastPerformance"
    /// Whether the editor shows an exercise's instructions and note under
    /// its name. On until it is turned off.
    static let showExerciseTexts = "showExerciseTexts"
    /// Whether an exercise that tracks sets arrives in a workout with a first
    /// set already there.
    static let startWithOneSet = "startWithOneSet"
    /// Whether a workout being trained guides through its sets: the set to
    /// do highlighted, Next on the keyboard, and the next set's first field
    /// once a rest is over. On until it is turned off.
    static let guideThroughWorkout = "guideThroughWorkout"
    /// Whether a day variant not trained within its week is deleted rather
    /// than archived. Off until it is turned on.
    static let deleteUnusedDayVariants = "deleteUnusedDayVariants"
    /// The rest after a set, in seconds, for an exercise without one of its
    /// own; 0 is no rest timer. Unset means `RestDuration.defaultSeconds`.
    static let defaultRestSeconds = "defaultRestSeconds"
    /// How long to rest between the two sides of a Same Weight set; 0 is no
    /// timer. Unset means `RestDuration.defaultBetweenSidesSeconds`.
    static let betweenSidesRestSeconds = "betweenSidesRestSeconds"
    /// A `SideLayout` raw value: how the editor shows an exercise logged left
    /// and right apart. Unset means `SideLayout.standard`.
    static let sideLayout = "sideLayout"
    static let showActivityGraph = "showActivityGraph"
    static let showActivityWeekdays = "showActivityWeekdays"
    static let showActivityLegend = "showActivityLegend"
    static let historyPeriod = "historyPeriod"
    /// The custom range's bounds as reference-date intervals; 0 means unset,
    /// which on the end side stands for "up to today".
    static let historyCustomStart = "historyCustomStart"
    static let historyCustomEnd = "historyCustomEnd"
    /// A `WeightUnit` raw value. Unset means kilograms — the unit everything is
    /// stored in, and the one the app has always shown.
    static let weightUnit = "weightUnit"
    /// A `MuscleFilter.stored` value: the muscle the picker is narrowed to.
    /// Only the picker's is kept: it opens anew for every exercise of a workout.
    static let pickerMuscleFilter = "pickerMuscleFilter"
    /// Whether exercises show as big pictures rather than a list, in the
    /// Exercises tab and in the picker alike. Unset means the list.
    static let exercisesAsGrid = "exercisesAsGrid"
    /// An `EffortScale` raw value: the scale a newly added exercise is rated
    /// on. Unset means easy, normal, hard.
    static let effortScale = "effortScale"
    /// A `BodyFigure` raw value: the figure the muscle heat map is drawn on.
    /// Unset means male.
    static let bodyFigure = "bodyFigure"
    /// A `HeatMapPeriod` raw value: how far back the heat map looks. Unset
    /// means the last month.
    static let heatMapPeriod = "heatMapPeriod"
    /// A `GymsTab.Part` raw value: whether the Gyms tab shows the gyms or the
    /// machines. Unset means the gyms.
    static let gymsTabPart = "gymsTabPart"
    /// A `ProgressMetric` raw value: the number an exercise's progress graph
    /// was last switched to. Unset means the estimated one-rep max.
    static let progressMetric = "progressMetric"
    /// A `CategoryFilter.stored` value: the categories the heat map counts.
    /// Unset means Strength alone.
    static let heatMapCategories = "heatMapCategories"
    /// An `ActivityGraphs.stored` value: the categories of the activity
    /// graphs, in order. Unset means Strength, then Cardio.
    static let activityGraphs = "activityGraphs"
    /// The build whose "What's New" was last closed, or the newest build
    /// launched when there was nothing to show. Unset (0) means none was ever
    /// remembered — see `WhatsNew`.
    static let whatsNewSeenBuild = "whatsNewSeenBuild"
    /// A `KeptOwnExercises.stored` value: the own exercises the review of
    /// My Exercises was told to keep, so it does not bring them up again.
    static let keptOwnExercises = "keptOwnExercises"
    /// How many own exercises the review moved to the catalog, for
    /// `CatalogReviewPrompt` to tell a done review from an ignored one.
    static let catalogMovedCount = "catalogMovedCount"
    /// Set by "Don't Show This Again" on the review at launch.
    static let catalogReviewDontShow = "catalogReviewDontShow"
    /// When the review was last shown at launch, as a reference-date
    /// interval; 0 means never.
    static let catalogReviewLastShown = "catalogReviewLastShown"
    /// Set once `SidesSettlement` has run: the step after the update that
    /// brought bilateral and unilateral happens a single time.
    static let sidesSettled = "sidesSettled"
    /// Set once `SidesSettlement.dropUnusedOnce` has run, with build 22.
    static let unusedDropped = "unusedDropped"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.collapseOtherExercises) private var collapseOtherExercises = false
    @AppStorage(SettingsKey.showLastPerformance) private var showLastPerformance = true
    @AppStorage(SettingsKey.showExerciseTexts) private var showExerciseTexts = true
    @AppStorage(SettingsKey.startWithOneSet) private var startWithOneSet = false
    @AppStorage(SettingsKey.guideThroughWorkout) private var guideThroughWorkout = true
    @AppStorage(SettingsKey.deleteUnusedDayVariants) private var deleteUnusedDayVariants = false
    @AppStorage(SettingsKey.defaultRestSeconds) private var defaultRestSeconds = RestDuration.defaultSeconds
    @AppStorage(SettingsKey.betweenSidesRestSeconds) private var betweenSidesRestSeconds = RestDuration.defaultBetweenSidesSeconds
    @AppStorage(SettingsKey.showActivityGraph) private var showActivityGraph = true
    @AppStorage(SettingsKey.showActivityWeekdays) private var showActivityWeekdays = true
    @AppStorage(SettingsKey.showActivityLegend) private var showActivityLegend = false
    @AppStorage(SettingsKey.weightUnit) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @AppStorage(SettingsKey.effortScale) private var effortScaleRaw = EffortScale.defaultForNewEntries.rawValue
    @AppStorage(SettingsKey.sideLayout) private var sideLayout = SideLayout.standard
    @AppStorage(SettingsKey.bodyFigure) private var bodyFigureRaw = BodyFigure.male.rawValue

    private var weightUnit: Binding<WeightUnit> {
        Binding(
            get: { WeightUnit(rawValue: weightUnitRaw) ?? .kilograms },
            set: { weightUnitRaw = $0.rawValue }
        )
    }

    private var effortScale: Binding<EffortScale> {
        Binding(
            get: { EffortScale(rawValue: effortScaleRaw) ?? .defaultForNewEntries },
            set: { effortScaleRaw = $0.rawValue }
        )
    }

    private var bodyFigure: Binding<BodyFigure> {
        Binding(
            get: { BodyFigure(rawValue: bodyFigureRaw) ?? .male },
            set: { bodyFigureRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Weight Unit", selection: weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                } header: {
                    Text("Units")
                } footer: {
                    // Formatted, not spelled out, so the example reads like
                    // the weights it describes.
                    Text("The unit you enter and read weights in. Sets are always stored in kilograms, so switching re-reads your whole history in the new unit — a set logged as 135 lb shows as \(WeightUnit.kilograms.formatted(kilograms: WeightUnit.pounds.kilograms(from: 135))).")
                }

                Section {
                    Toggle("Show Activity Graph", isOn: $showActivityGraph)
                    Toggle("Show Weekdays", isOn: $showActivityWeekdays)
                        .disabled(!showActivityGraph)
                    Toggle("Show Legend", isOn: $showActivityLegend)
                        .disabled(!showActivityGraph)
                } header: {
                    Text("Overview")
                } footer: {
                    Text("Shows the last twelve months of training on the workout list, one graph per category. Swipe across a graph's title to turn to the next one; its menu picks the categories. The legend spells out what the shades mean.")
                }

                Section {
                    Picker("Gender", selection: bodyFigure) {
                        ForEach(BodyFigure.allCases) { figure in
                            Text(figure.name).tag(figure)
                        }
                    }
                } header: {
                    Text("Muscle Heat Map")
                } footer: {
                    Text("The figure the heat map on the Statistics tab is drawn on. Nothing else depends on it.")
                }

                Section {
                    Toggle("Collapse Other Exercises", isOn: $collapseOtherExercises)
                    Toggle("Show Last Performance", isOn: $showLastPerformance)
                    Toggle("Show Instructions and Notes", isOn: $showExerciseTexts)
                    Toggle("Start with One Set", isOn: $startWithOneSet)
                    Toggle("Guide Through Workout", isOn: $guideThroughWorkout)
                    Picker("Rest After a Set", selection: $defaultRestSeconds) {
                        ForEach(RestDuration.choices, id: \.self) { seconds in
                            Text(RestDuration.text(seconds)).tag(seconds)
                        }
                    }
                    Picker("Rest Between Sides", selection: $betweenSidesRestSeconds) {
                        ForEach(RestDuration.choices, id: \.self) { seconds in
                            Text(RestDuration.text(seconds)).tag(seconds)
                        }
                    }
                    Picker("Rate Effort", selection: effortScale) {
                        ForEach(EffortScale.allCases) { scale in
                            Text(scale.name).tag(scale)
                        }
                    }
                    Picker("Show Left and Right", selection: $sideLayout) {
                        ForEach(SideLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                } header: {
                    Text("Workout Editor")
                } footer: {
                    Text("Collapsing keeps only the exercise you are working on expanded. Last Performance puts what you logged for that exercise the time before under its name, so you can see what to beat without opening the history. Instructions and Notes puts an exercise's instructions and note there too; off, the note button still opens them. Start with One Set adds the first set the moment an exercise is added, instead of leaving it empty. A set counts once it is ticked off. Guide Through Workout highlights the set to do next; Next on the keyboard goes from weight to reps and then ticks the set off, and when the rest is over the next set is ready to type into. Rate Effort is how newly added exercises rate their sets — Reps in Reserve counts the reps you had left, 0 meaning failure. Exercises already logged keep the way they were rated. Show Left and Right is for exercises logged L/R: a tab per side, or one list going from side to side. These are what every workout starts with; the editor's own Editor Settings change them for one workout.")
                }

                Section {
                    Toggle("Delete Unused Variants", isOn: $deleteUnusedDayVariants)
                } header: {
                    Text("Templates")
                } footer: {
                    Text("Adjust for Today in a template's menu makes a variant of it for one day, first in the row, while the template stays as it is. Once you finish a workout started from the variant, the variant is gone. One you do not use stays for a week and then goes to the archive — or, with this on, is deleted.")
                }

                Section {
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("FAQ", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        ReleaseNotesView(notes: .bundled)
                    } label: {
                        Label("What's New", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Where the gestures and the small icons are, and what the one-sided modes do. What's New lists what each build brought.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(
            for: AppSchema.models,
            inMemory: true
        )
}
