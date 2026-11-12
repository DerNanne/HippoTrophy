import SwiftUI

/// The date and time of a workout, in a sheet of its own.
///
/// A sheet rather than a popover: on iPhone the popover takes its width from
/// the pill that opens it and squeezes the graphical picker into a column.
struct WorkoutDateSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // The time has a picker of its own: the graphical one with both
            // components measures its time row short, and it shows clipped and
            // empty until tapped.
            VStack(spacing: 12) {
                DatePicker("Workout Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Workout Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// One exercise's instructions and note, edited as drafts the caller writes
/// back on Save. The instructions are the plan for this time and travel
/// with copies and templates; the note is what happened, and stays. Both
/// show at once rather than behind tabs: the sheet has the room, and
/// neither has to be looked for. A template is never trained, so it has
/// instructions only.
struct ExerciseNoteSheet: View {
    let exerciseName: String
    let isTemplate: Bool
    @Binding var instructions: String
    @Binding var note: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tempo, range, intensity, setup", text: $instructions, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("How to do it this time. Copies and templates take it along.")
                }
                if !isTemplate {
                    Section {
                        TextField("How it went", text: $note, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    } header: {
                        Text("Note")
                    } footer: {
                        Text("What happened in this workout. It stays here.")
                    }
                }
            }
            .navigationTitle(exerciseName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: onSave)
                }
            }
        }
    }
}
