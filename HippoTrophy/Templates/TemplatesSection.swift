import SwiftUI
import SwiftData

/// How the start screen opens the editor: on something made for it, which
/// is inserted first and gone again on Cancel, or on a template that is
/// already there.
enum EditorOpening: Equatable {
    /// Made for the editor; `failure` is said when inserting it fails.
    case new(failure: String)
    case existing
}

/// The "Templates" section of the start screen: the shelf, the way to the
/// archived templates, and everything the shelf's menus do. Opening the
/// editor is the start screen's, which owns it. Each time the screen comes
/// up, the day variants whose week is over are put away.
struct TemplatesSection: View {
    /// Whether a workout can start: not while one is being trained.
    let canStart: Bool
    /// Opens the editor; the third is the day variant a workout started
    /// from, which its Save uses up.
    let open: (WorkoutSession, EditorOpening, WorkoutSession?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.deleteUnusedDayVariants) private var deleteUnusedDayVariants = false
    @Query(filter: WorkoutSession.templates) private var templates: [WorkoutSession]
    @State private var renamingTemplate: WorkoutSession?
    @State private var templateName = ""
    @State private var showArchived = false
    /// The template looked at before starting from it.
    @State private var previewing: WorkoutSession?
    /// Set by Start Workout in the preview, acted on once the preview has
    /// closed: the editor cannot cover the screen while the sheet still does.
    @State private var startAfterPreview: WorkoutSession?
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var shelf: TemplateShelf { TemplateShelf(templates) }

    var body: some View {
        Section {
            TemplateShelfView(templates: shelf.templates, actions: actions)
                .sheet(isPresented: $showArchived) {
                    ArchivedTemplatesView()
                }
                .sheet(item: $previewing, onDismiss: startIfAsked) { template in
                    NavigationStack {
                        WorkoutDetailView(session: template, canStartWorkout: canStart) {
                            startAfterPreview = template
                            previewing = nil
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { previewing = nil }
                            }
                        }
                    }
                }
                .alert(
                    "Rename Template",
                    isPresented: Binding(get: { renamingTemplate != nil }, set: { if !$0 { renamingTemplate = nil } })
                ) {
                    TextField("Name", text: $templateName)
                    Button("Cancel", role: .cancel) { renamingTemplate = nil }
                    Button("Rename") { rename() }
                }
                .alert("Templates", isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(alertMessage)
                }
        } header: {
            header
        }
        .onAppear(perform: putAwayExpiredVariants)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { putAwayExpiredVariants() }
        }
        // The cards scroll in from the screen's edge, like the activity
        // graphs above.
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listSectionMargins(.horizontal, 0)
        .listRowSeparator(.hidden)
    }

    /// The header carries the way to the archived templates, there only
    /// when there are some.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Templates")
            Spacer(minLength: 8)
            if !shelf.archived.isEmpty {
                Button("Archived (\(shelf.archived.count))") {
                    showArchived = true
                }
                .font(.footnote)
                .textCase(nil)
            }
        }
        // The section has no margins of its own; the header keeps the list's.
        .padding(.horizontal, 16)
    }

    private var actions: TemplateShelfView.Actions {
        TemplateShelfView.Actions(
            start: { template in
                previewing = template
            },
            edit: { template in
                open(template, .existing, nil)
            },
            adjustForToday: { template in
                let variant = DayVariants.variant(of: template, on: .now)
                shelf.placeFirst(variant)
                open(variant, .new(failure: "Could not adjust template."), nil)
            },
            rename: { template in
                templateName = template.name
                renamingTemplate = template
            },
            duplicate: { template in
                let copy = template.templateCopy(named: TemplateShelf.duplicateName(of: template.name))
                modelContext.insert(copy)
                withAnimation {
                    shelf.place(copy, after: template)
                }
                save("Could not duplicate template.")
            },
            archive: { template in
                withAnimation {
                    shelf.archive(template)
                }
                save("Could not archive template.")
            },
            move: { template, target in
                shelf.move(template, to: target)
            },
            finishMoving: {
                save("Could not reorder templates.")
            },
            create: {
                let template = WorkoutSession()
                template.isTemplate = true
                shelf.placeFirst(template)
                open(template, .new(failure: "Could not create template."), nil)
            }
        )
    }

    private func startIfAsked() {
        guard let template = startAfterPreview else { return }
        startAfterPreview = nil
        open(template.trainingCopy(dated: .now, in: modelContext), .new(failure: "Could not start workout."), template.plannedFor == nil ? nil : template)
    }

    /// The day variants whose week is over leave the shelf: archived, or
    /// deleted when the setting says so.
    private func putAwayExpiredVariants() {
        guard DayVariants.putAwayExpired(in: modelContext, deleting: deleteUnusedDayVariants) else { return }
        save("Could not put away last week's variants.")
    }

    /// A name left empty keeps the one there was: a template without one
    /// would be a blank card.
    private func rename() {
        defer { renamingTemplate = nil }
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template = renamingTemplate, !name.isEmpty else { return }
        template.name = name
        save("Could not rename template.")
    }

    private func save(_ fallbackMessage: String) {
        guard let failure = modelContext.save(reporting: fallbackMessage) else { return }
        alertMessage = failure
        showAlert = true
    }
}
