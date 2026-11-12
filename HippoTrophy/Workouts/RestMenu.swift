import SwiftUI

/// The rest after a set of an exercise, beside its Add Set: it shows the rest
/// that applies and opens the choice. Its own rest is the exercise's, so it
/// holds in every workout and template; "Default" follows the setting.
struct RestMenu: View {
    /// The exercise's own rest, nil when it follows the setting.
    let seconds: Int?
    let defaultSeconds: Int
    let onChange: (Int?) -> Void

    private var applying: Int {
        RestDuration.seconds(exercise: seconds, setting: defaultSeconds) ?? 0
    }

    var body: some View {
        Menu {
            Picker("Rest After a Set", selection: Binding(get: { seconds }, set: onChange)) {
                Text("Default (\(RestDuration.text(defaultSeconds)))").tag(Int?.none)
                ForEach(RestDuration.choices, id: \.self) { choice in
                    Text(RestDuration.text(choice)).tag(Int?.some(choice))
                }
            }
        } label: {
            Label(RestDuration.text(applying), systemImage: applying > 0 ? "timer" : "clock.badge.xmark")
                .font(.subheadline.monospacedDigit())
                // Its own rest stands out; the default stays quiet.
                .foregroundStyle(seconds == nil ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Rest after a set")
        .accessibilityValue(applying > 0 ? DurationFormat.text(forSeconds: applying) : "Off")
    }
}

/// What ticking a set off does beyond the tick — the editor starts a rest.
/// Handed down rather than through every card, because a tick is the set
/// row's alone and the decision the editor's.
extension EnvironmentValues {
    @Entry var setTicked: (SetEntry) -> Void = { _ in }
    /// The first of a Same Weight set's two ticks — the editor starts the
    /// rest between its sides.
    @Entry var setSideTicked: (SetEntry) -> Void = { _ in }
    /// The field of a set the cursor is in, by its value's id — the editor's,
    /// so Next and the end of a rest can move it from set to set. Nil where
    /// nothing guides.
    @Entry var setFieldFocus: FocusState<UUID?>.Binding? = nil
}
