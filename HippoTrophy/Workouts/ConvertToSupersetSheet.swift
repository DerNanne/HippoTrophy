import SwiftUI

/// Picks which other exercise in this workout joins into a superset with the
/// one long-pressed. Only exercises not already paired are offered — merging
/// into an existing pair is not this dialog's job.
struct ConvertToSupersetSheet: View {
    let exercise: ExerciseEntry
    let candidates: [ExerciseEntry]
    let onConfirm: (ExerciseEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("Nothing else in this workout can be paired — every other exercise is already part of a superset.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(candidates) { candidate in
                            Button {
                                onConfirm(candidate)
                                dismiss()
                            } label: {
                                Text(candidate.name)
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text("Pair \"\(exercise.name)\" With")
                    } footer: {
                        Text("Every set stays as logged and they line up in turns: A, B, A, B. The one higher in the workout is A. An exercise logged left and right on both sides cannot be paired.")
                    }
                }
            }
            .navigationTitle("Convert to Superset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
