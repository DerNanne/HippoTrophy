import SwiftUI
import SwiftData

/// What a workout is made of: the exercises, and nothing else, so the list
/// starts right under its filters.
struct ExercisesTab: View {
    /// Goes back into the workout being trained, from its banner.
    let openRunningWorkout: () -> Void

    var body: some View {
        NavigationStack {
            ManageExercisesView()
                // Inline: above a bar the large title has no room to stand and
                // leaves an empty band until the list is scrolled.
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaBar(edge: .top) {
                    RunningWorkoutSlot(open: openRunningWorkout)
                        // As under the search: no names to read behind it.
                        .background(Color(.systemGroupedBackground))
                }
        }
    }
}

#Preview {
    ExercisesTab(openRunningWorkout: {})
        .modelContainer(for: AppSchema.models, inMemory: true)
}
