import SwiftUI
import SwiftData

/// The banner while a workout is being trained, nothing otherwise. Every tab
/// shows the same one, so a workout left behind is never out of sight.
struct RunningWorkoutSlot: View {
    @Environment(\.modelContext) private var modelContext
    private let runningWorkout = RunningWorkoutCenter.shared
    let open: () -> Void

    var body: some View {
        if let running = runningWorkout.running, let session = workout(withID: running.sessionID) {
            RunningWorkoutBanner(name: session.name, startedAt: running.startedAt, rest: RestTimerCenter.shared.timer, open: open)
        }
    }

    /// Looked up in the store rather than in a query, which has not always
    /// caught up with a workout just started.
    private func workout(withID id: UUID) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

/// The workout being trained, at the top of a tab while it is left: its name,
/// its clock and the rest, if one runs. A tap goes back in.
struct RunningWorkoutBanner: View {
    let name: String
    let startedAt: Date?
    let rest: RestTimer?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.green, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? "Workout" : name)
                        .font(.headline)
                        .lineLimit(1)
                    restLine
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let startedAt {
                    Text(startedAt, style: .timer)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .accessibilityLabel("Workout time")
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .accessibilityHint("Goes back to the workout")
    }

    /// The rest counts down here as it does in the editor's bar, on the
    /// system's clock.
    @ViewBuilder private var restLine: some View {
        if let rest {
            if let paused = rest.pausedRemaining {
                Text("Rest paused · \(DurationFormat.text(forSeconds: Int(paused.rounded(.up))))")
            } else {
                let start = rest.endsAt.addingTimeInterval(-rest.duration)
                Text("Rest · \(Text(timerInterval: start...max(rest.endsAt, start.addingTimeInterval(1)), countsDown: true))")
                    .monospacedDigit()
            }
        } else {
            Text("In progress")
        }
    }
}
