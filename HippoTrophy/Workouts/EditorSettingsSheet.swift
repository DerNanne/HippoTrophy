import SwiftUI

/// The Workout Editor section of Settings, from inside the editor: changes
/// here hold for this workout, and Settings keeps what every workout starts
/// with. What only happens while training is left out of anything else.
struct EditorSettingsSheet: View {
    @Binding var overrides: EditorSettingsOverrides
    let defaults: EditorSettings
    let isBeingTrained: Bool
    @Environment(\.dismiss) private var dismiss

    private var settings: EditorSettings {
        overrides.applied(to: defaults)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Collapse Other Exercises", isOn: binding(\.collapseOtherExercises, \.collapseOtherExercises))
                    Toggle("Show Last Performance", isOn: binding(\.showLastPerformance, \.showLastPerformance))
                    Toggle("Show Instructions and Notes", isOn: binding(\.showExerciseTexts, \.showExerciseTexts))
                    Toggle("Start with One Set", isOn: binding(\.startWithOneSet, \.startWithOneSet))
                    if isBeingTrained {
                        Toggle("Guide Through Workout", isOn: binding(\.guideThroughWorkout, \.guideThroughWorkout))
                        restPicker("Rest After a Set", binding(\.defaultRestSeconds, \.defaultRestSeconds))
                        restPicker("Rest Between Sides", binding(\.betweenSidesRestSeconds, \.betweenSidesRestSeconds))
                    }
                    Picker("Rate Effort", selection: binding(\.effortScale, \.effortScale)) {
                        ForEach(EffortScale.allCases) { scale in
                            Text(scale.name).tag(scale)
                        }
                    }
                    Picker("Show Left and Right", selection: binding(\.sideLayout, \.sideLayout)) {
                        ForEach(SideLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                } footer: {
                    Text("These hold for this workout only. What every workout starts with is in Settings → Workout Editor. Rate Effort is for exercises added from now on; those already here keep theirs.")
                }

                if !overrides.isEmpty {
                    Section {
                        Button("Reset to Defaults") {
                            overrides = EditorSettingsOverrides()
                        }
                    }
                }
            }
            .navigationTitle("Editor Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func restPicker(_ title: String, _ selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(RestDuration.choices, id: \.self) { seconds in
                Text(RestDuration.text(seconds)).tag(seconds)
            }
        }
    }

    private func binding<Value: Equatable>(
        _ override: WritableKeyPath<EditorSettingsOverrides, Value?>,
        _ setting: KeyPath<EditorSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: setting] },
            set: { overrides.set(override, to: $0, default: defaults[keyPath: setting]) }
        )
    }
}

/// Whether the cards below show an exercise's instructions and note: Settings,
/// or what this workout changed. Handed down rather than through every card.
extension EnvironmentValues {
    @Entry var showsExerciseTexts = true
}
