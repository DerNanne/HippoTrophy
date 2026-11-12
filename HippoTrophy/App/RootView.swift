import SwiftUI
import SwiftData

/// The four places the app is made of. Each tab keeps its own navigation, so
/// leaving one for another and coming back finds it where it was.
struct RootView: View {
    private enum Tab {
        case workouts, exercises, gyms, statistics
    }

    @State private var tab = Tab.workouts
    @State private var showRunningWorkout = false

    var body: some View {
        TabView(selection: $tab) {
            WorkoutsView(showRunningWorkout: $showRunningWorkout)
                .tabItem { Label("Workouts", systemImage: "house") }
                .tag(Tab.workouts)

            ExercisesTab(openRunningWorkout: openRunningWorkout)
                .tabItem { Label("Exercises", systemImage: "dumbbell") }
                .tag(Tab.exercises)

            GymsTab(openRunningWorkout: openRunningWorkout)
                .tabItem { Label("Gyms", image: "GymMachines") }
                .tag(Tab.gyms)

            NavigationStack {
                MuscleGroupsView()
                    .safeAreaInset(edge: .top) {
                        RunningWorkoutSlot(open: openRunningWorkout)
                    }
            }
            .tabItem { Label("Statistics", systemImage: "chart.bar") }
            .tag(Tab.statistics)
        }
    }

    /// The workout lives on the Workouts tab's stack, so going back into it
    /// from another tab goes there first.
    private func openRunningWorkout() {
        tab = .workouts
        showRunningWorkout = true
    }
}

#Preview {
    RootView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
