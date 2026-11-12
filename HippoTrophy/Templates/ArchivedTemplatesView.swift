import SwiftUI
import SwiftData

/// The templates put away: each can come back to the shelf, first in line,
/// or go for good. Deleting is only here — a template has to be archived
/// before it can be deleted, so the shelf's menu holds nothing that cannot
/// be taken back. A day variant keeps its badge here, so it is told apart
/// from the template it was made of, and comes back as today's.
struct ArchivedTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: WorkoutSession.templates) private var templates: [WorkoutSession]
    @State private var pendingDeletion: WorkoutSession?
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var shelf: TemplateShelf { TemplateShelf(templates) }

    var body: some View {
        NavigationStack {
            List {
                if shelf.archived.isEmpty {
                    Text("No archived templates.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shelf.archived) { template in
                    row(template)
                }
            }
            .navigationTitle("Archived Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Delete \"\(pendingDeletion?.name ?? "")\"?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion
            ) { template in
                Button("Delete", role: .destructive) { delete(template) }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text("The template is gone for good. Workouts started from it stay as they are.")
            }
            .alert("Templates", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func row(_ template: WorkoutSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.headline)
                if let day = template.plannedFor {
                    DayVariantBadge(day: day)
                }
                if !template.exercises.isEmpty {
                    Text(TemplateShelf.exerciseLine(of: template))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                    restore(template)
                } label: {
                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    pendingDeletion = template
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Template Actions")
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                pendingDeletion = template
            }
            Button("Unarchive") {
                restore(template)
            }
            .tint(.accentColor)
        }
    }

    private func restore(_ template: WorkoutSession) {
        shelf.restore(template, on: .now)
        save("Could not unarchive template.")
    }

    private func delete(_ template: WorkoutSession) {
        modelContext.delete(template)
        pendingDeletion = nil
        save("Could not delete template.")
    }

    private func save(_ fallbackMessage: String) {
        guard let failure = modelContext.save(reporting: fallbackMessage) else { return }
        alertMessage = failure
        showAlert = true
    }
}
