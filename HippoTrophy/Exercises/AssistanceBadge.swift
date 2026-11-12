import SwiftUI

/// The capsule that marks whether an exercise was assisted — the sibling of
/// `UnilateralModeBadge`, drawn the same way so the two read as one row of
/// facts about the entry.
struct AssistanceBadge: View {
    let assistance: Assistance

    var body: some View {
        Text(assistance.shortTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(assistance.isAssisted ? Color.blue : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((assistance.isAssisted ? Color.blue : Color.secondary).opacity(0.14))
            )
            .fixedSize()
            .accessibilityLabel(assistance.title)
    }
}

/// The capsule as a switch, for the workout editor's cards: it shows whether
/// the sets were assisted and opens the choice.
struct AssistanceMenu: View {
    let assistance: Assistance
    let choices: [Assistance]
    let onChange: (Assistance) -> Void

    var body: some View {
        Menu {
            Picker("Assistance", selection: Binding(get: { assistance }, set: onChange)) {
                ForEach(choices, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
        } label: {
            AssistanceBadge(assistance: assistance)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assistance: \(assistance.title)")
    }
}
