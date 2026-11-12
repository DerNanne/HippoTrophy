import SwiftUI

/// Reorders the sets of one card in a list of their own, the way "Reorder
/// Exercises" does the cards. A handle on every set row took width a row with
/// three fields needs, and was easy to catch while logging; moving a set is
/// rare enough to be worth the trip through the exercise's menu.
struct SetReorderView: View {
    @Environment(\.dismiss) private var dismiss

    /// What the card is called: the exercise, the side on screen, the pair.
    let title: String
    let rows: [SetReorderRow]
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(title) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            Text(row.values)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove(perform: onMove)
                }
            }
            .navigationTitle("Reorder Sets")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One set as the reorder list shows it: which set, and what is in it, so
/// two sets of the same number can be told apart.
struct SetReorderRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let values: String

    /// `name` says which set it is — "Set 2", "Left · Set 2", the exercise
    /// in a superset. The values read as a workout's page shows them, the
    /// empty ones left out.
    init(_ set: SetEntry, name: String, unit: WeightUnit) {
        id = set.id
        title = name
        let filled = set.sortedValues.filter { !$0.isEmpty }.map { $0.displayText(unit: unit) }
        values = filled.isEmpty ? "Nothing logged" : filled.joined(separator: " · ")
    }
}
