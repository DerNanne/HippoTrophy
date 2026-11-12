import SwiftUI
import SwiftData

struct ExerciseReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: WorkoutSession
    let onSaveError: (String) -> Void

    private var sortedExercises: [ExerciseEntry] {
        session.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// A row per card in the editor: a superset is one row, so it moves as
    /// a whole and the list shows the order the editor will.
    private var groups: [[ExerciseEntry]] {
        ExerciseGrouping.groups(sortedExercises)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.first?.id) { group in
                    if group.count > 1 {
                        Label(group.map(\.name).joined(separator: " + "), systemImage: "link")
                    } else {
                        Text(group.first?.name ?? "")
                    }
                }
                .onMove(perform: moveExercises)
            }
            .navigationTitle("Reorder Exercises")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        let orderedExercises = ExerciseGrouping.reordered(sortedExercises, movingGroups: source, to: destination)

        for (index, exercise) in orderedExercises.enumerated() {
            exercise.orderIndex = index
        }

        if let failure = modelContext.save(reporting: "Could not reorder exercises.") {
            onSaveError(failure)
        }
    }
}
