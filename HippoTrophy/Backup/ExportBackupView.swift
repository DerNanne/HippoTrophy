import SwiftUI

/// Which parts of a backup to write. Everything is on by default: a backup that
/// silently omits a section is the one failure mode worth designing against.
struct BackupSelection {
    var exercises = true
    var workouts = true
    var templates = true
    /// Go along with the exercises and the machines. On, a file with photos
    /// is a ZIP.
    var photos = true

    var isEmpty: Bool { !exercises && !workouts && !templates }
}

/// The count and size of the photos an export takes along: "2 · 1.3 MB". Size
/// is what the choice is about, so it stands beside the count. A dot between
/// them, not a comma: where the comma is the decimal mark, "2, 1,3 MB" reads
/// as one number.
nonisolated enum PhotoSummary {
    static func text(sizes: [Int], locale: Locale = .current) -> String {
        let size = Int64(sizes.reduce(0, +)).formatted(.byteCount(style: .file).locale(locale))
        return "\(sizes.count) · \(size)"
    }
}

/// Picks what goes into the file before the export sheet opens.
struct ExportBackupView: View {
    /// The user's own exercises. The file carries the catalog's too, so an
    /// entry finds its exercise anywhere, but they are not the user's to count.
    let exerciseCount: Int
    let workoutCount: Int
    /// Archived ones included.
    let templateCount: Int
    /// The size in bytes of each photo of the user's own exercises.
    let exercisePhotos: [Int]
    /// The size in bytes of each machine's photo. Machines always go along.
    let machinePhotos: [Int]
    /// Set on Export, left nil on Cancel; read by the caller once this is dismissed.
    @Binding var selection: BackupSelection?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = BackupSelection()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $draft.exercises) {
                        LabeledContent("My Exercises", value: "\(exerciseCount)")
                    }
                    if hasPhotos {
                        Toggle(isOn: $draft.photos) {
                            LabeledContent("Photos", value: photoSummary)
                        }
                        .disabled(photos.isEmpty)
                    }
                    Toggle(isOn: $draft.workouts) {
                        LabeledContent("Workouts", value: "\(workoutCount)")
                    }
                    Toggle(isOn: $draft.templates) {
                        LabeledContent("Templates", value: "\(templateCount)")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Everything you leave on lands in one file. Turn parts off to share just those — your exercise list without your training history, for example.")
                        if hasPhotos {
                            Text("With photos, the file is a ZIP. Without them it is much smaller, but an import brings no photos back.")
                        }
                    }
                }
            }
            .navigationTitle("Export Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selection = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        selection = draft
                        dismiss()
                    }
                    .disabled(draft.isEmpty)
                }
            }
        }
    }

    private var hasPhotos: Bool { !exercisePhotos.isEmpty || !machinePhotos.isEmpty }

    /// The photos that would go: the exercises' only with the exercises.
    private var photos: [Int] {
        (draft.exercises ? exercisePhotos : []) + machinePhotos
    }

    private var photoSummary: String {
        PhotoSummary.text(sizes: photos)
    }
}
