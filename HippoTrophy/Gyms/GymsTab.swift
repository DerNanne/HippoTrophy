import SwiftUI
import SwiftData

/// Where the workouts happen: the gyms and the machines standing in them. One
/// switch at the top, since a machine is looked for either way.
struct GymsTab: View {
    enum Part: String, CaseIterable, Identifiable {
        case gyms = "Gyms"
        case machines = "Machines"

        var id: Self { self }
    }

    /// Goes back into the workout being trained, from its banner.
    let openRunningWorkout: () -> Void

    @AppStorage(SettingsKey.gymsTabPart) private var partRaw = Part.gyms.rawValue

    private var part: Binding<Part> {
        Binding(
            get: { Part(rawValue: partRaw) ?? .gyms },
            set: { partRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch part.wrappedValue {
                case .gyms: GymsView()
                case .machines: MachinesView()
                }
            }
            // Inline: above a bar the large title has no room to stand and
            // leaves an empty band until the list is scrolled.
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .top) {
                VStack(spacing: 0) {
                    RunningWorkoutSlot(open: openRunningWorkout)
                    Picker("Show", selection: part) {
                        ForEach(Part.allCases) { part in
                            Text(part.rawValue).tag(part)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                // No names to read behind the switch.
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}

#Preview {
    GymsTab(openRunningWorkout: {})
        .modelContainer(for: AppSchema.models, inMemory: true)
}
