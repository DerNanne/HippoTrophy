import SwiftUI

/// What an import hands back: what to bring in, and how the questions the
/// planner raised were answered.
struct ImportChoice {
    var selection: ImportSelection
    var decisions: ImportDecisions
}

/// Shows what a picked file holds, then — where the file and the device
/// disagree about an exercise — asks before anything is written.
struct ImportBackupView: View {
    let file: BackupFile
    /// Photos the file names that did not come with it.
    var missingPhotoCount = 0
    let plan: ImportPlan
    @Binding var choice: ImportChoice?

    @Environment(\.dismiss) private var dismiss
    @State private var selection = ImportSelection()
    @State private var decisions = ImportDecisions()
    @State private var reviewing = false

    /// Catalog exercises come with every app; only the user's own are
    /// worth a number — see `BackupFile.ownExerciseCount`.
    private var exerciseCount: Int { file.ownExerciseCount }
    private var workoutCount: Int { file.workouts?.count ?? 0 }
    private var templateCount: Int { file.templates?.count ?? 0 }

    /// The exercises with a question attached, in file order.
    private var openItems: [ImportPlanner.ExerciseItem] {
        plan.exercises.filter { $0.outcome.needsDecision }
    }

    private var needsReview: Bool { selection.exercises && !openItems.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "My Exercises", count: exerciseCount, isOn: $selection.exercises)
                    row(title: "Workouts", count: workoutCount, isOn: $selection.workouts)
                    if workoutCount > 0 && selection.workouts {
                        Picker("", selection: $selection.replaceWorkouts) {
                            Text("Add").tag(false)
                            Text("Replace All").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    row(title: "Templates", count: templateCount, isOn: $selection.templates)
                } header: {
                    Text("Exported \(file.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle("Import Backup")
            .navigationDestination(isPresented: $reviewing) {
                ImportReviewView(items: openItems, decisions: $decisions) {
                    finish()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        choice = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(needsReview ? "Review" : "Import") {
                        if needsReview {
                            reviewing = true
                        } else {
                            finish()
                        }
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .onAppear {
                // A section the file does not carry cannot be imported, and an
                // "on" switch for it would promise something that is not there.
                selection.exercises = exerciseCount > 0
                selection.workouts = workoutCount > 0
                selection.templates = templateCount > 0
            }
        }
    }

    private func finish() {
        choice = ImportChoice(selection: selection, decisions: decisions)
        dismiss()
    }

    /// Every part of a backup gets a row, present or not, so the file's
    /// contents are readable at a glance instead of inferred from what is
    /// missing. A part the file does not carry is greyed out and cannot be
    /// switched on, because there would be nothing behind the switch.
    private func row(title: String, count: Int, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            LabeledContent(title, value: count > 0 ? "\(count)" : "Not in file")
        }
        .disabled(count == 0)
    }

    /// The photos an import of the selection brings: the exercises' only
    /// with the exercises, the machines' always, like the machines.
    private var photoCount: Int {
        let exercises = selection.exercises ? (file.exercises ?? []).filter { $0.photo != nil }.count : 0
        return exercises + (file.machines ?? []).filter { $0.photo != nil }.count
    }

    private var footerText: String {
        var text = ""
        if selection.workouts && selection.replaceWorkouts {
            text = "Replace All deletes every workout on this device first, then writes the ones from the file. Your exercises and templates are only ever added to.\n\n"
            if RunningWorkoutCenter.shared.running != nil {
                text += "⚠️ That includes the workout you are training right now.\n\n"
            }
        } else {
            text = "Workouts and templates already on this device are skipped. Exercises you already have stay as they are.\n\n"
        }
        if needsReview {
            let differing = CountFormat.text(openItems.count, "exercise in the file differs", "exercises in the file differ")
            text += "\(differing) from the one of the same name on this device, yours or the catalog's. You decide what happens next.\n\n"
        }
        if missingPhotoCount > 0 {
            text += "⚠️ \(CountFormat.text(missingPhotoCount, "photo", "photos")) named in the file \(missingPhotoCount == 1 ? "is" : "are") not with it. To bring photos along, pick the backup's ZIP file."
        } else if photoCount > 0 {
            text += "\(CountFormat.text(photoCount, "photo comes", "photos come")) along. An exercise or machine that already has one keeps it."
        }
        return text
    }
}
