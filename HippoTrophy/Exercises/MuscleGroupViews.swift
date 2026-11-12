import SwiftUI

/// The muscles under an exercise's name in a list. One line of plain text rather
/// than capsules: a row can carry three of them, and three capsules turn a list
/// into a wall.
struct MuscleGroupSummary: View {
    let groups: [MuscleGroup]
    /// Named after the main ones, lighter, so the line reads main first.
    var secondary: [MuscleGroup] = []

    var body: some View {
        if !groups.isEmpty || !secondary.isEmpty {
            (Text(groups.map(\.displayName).joined(separator: " · ")).foregroundStyle(.secondary)
                + Text(separator).foregroundStyle(.tertiary)
                + Text(secondary.map(\.displayName).joined(separator: " · ")).foregroundStyle(.tertiary))
                .font(.footnote)
                .accessibilityLabel(spoken)
        }
    }

    private var separator: String {
        groups.isEmpty || secondary.isEmpty ? "" : " · "
    }

    private var spoken: String {
        let main = "Muscle groups: \(groups.map(\.displayName).joined(separator: ", "))"
        guard !secondary.isEmpty else { return main }
        return main + "; secondary: \(secondary.map(\.displayName).joined(separator: ", "))"
    }
}

/// The muscles an exercise is filed under, as one row that names them and
/// opens the picker. Thirteen rows inline would be most of the exercise
/// editor, for something that is often left empty.
struct MuscleGroupsRow: View {
    @Binding var selection: MuscleSelection

    private var summary: String {
        let names = { (raw: [String]) in raw.compactMap(MuscleGroup.from(raw:)).map(\.displayName) }
        let main = names(selection.primary)
        let secondary = names(selection.secondary)
        if main.isEmpty && secondary.isEmpty { return "None" }
        return (main + secondary.map { "(\($0))" }).joined(separator: ", ")
    }

    var body: some View {
        NavigationLink {
            MuscleGroupsPage(selection: $selection)
        } label: {
            LabeledContent("Muscle Groups") {
                Text(summary)
                    .lineLimit(1)
            }
        }
    }
}

/// The picker on a page of its own, reached from the row or from the question
/// before saving without any.
struct MuscleGroupsPage: View {
    @Binding var selection: MuscleSelection

    var body: some View {
        List {
            Section {
                MuscleGroupPicker(selection: $selection)
            } footer: {
                Text("Main for what the exercise is for, Secondary for what it works along the way — a squat is for Quads and Glutes, with Adductors secondary. Tap a switch again to clear it. The picker and the exercise list find the exercise under its main muscle groups.")
            }
        }
        .navigationTitle("Muscle Groups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The muscles an exercise is filed with: each row has a switch for Main and
/// one for Secondary, at most one of them on.
struct MuscleGroupPicker: View {
    @Binding var selection: MuscleSelection

    var body: some View {
        ForEach(MuscleGroup.allCases) { muscle in
            let level = selection.level(of: muscle)
            HStack(spacing: 8) {
                Text(muscle.displayName)
                Spacer(minLength: 8)
                levelButton("Main", muscle: muscle, level: .primary, isOn: level == .primary)
                levelButton("Secondary", muscle: muscle, level: .secondary, isOn: level == .secondary)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func levelButton(_ title: String, muscle: MuscleGroup, level: MuscleSelection.Level, isOn: Bool) -> some View {
        let button = Button(title) {
            selection.toggle(muscle, level)
        }
        .controlSize(.small)
        .accessibilityLabel("\(muscle.displayName), \(title)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        if isOn {
            button.buttonStyle(.borderedProminent)
                .tint(level == .primary ? Color.accentColor : Color.gray)
        } else {
            button.buttonStyle(.bordered)
                .tint(.secondary)
        }
    }
}
