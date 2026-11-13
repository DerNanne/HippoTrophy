import SwiftUI
import UIKit
import SwiftData

extension Notification.Name {
    /// Posted once the message after an import is closed: what came in may
    /// hold exercises the sides assistant has to ask about, and it asks
    /// before anything else, not only at the next launch.
    static let backupImported = Notification.Name("HippoTrophy.backupImported")
}

/// A backup on its way in, before anything is read from it.
struct IncomingBackup: Identifiable {
    enum Source: Equatable {
        case file
        /// `backup.zip` from the sync server, with the etag it had.
        case server(etag: String?)
    }

    let id = UUID()
    let data: Data
    let source: Source
}

extension View {
    /// Everything after a backup is in hand: reading it, the planner, the
    /// review, writing it, and the message at the end. Set `incoming` to
    /// start; it is set back to nil at once.
    func backupImport(_ incoming: Binding<IncomingBackup?>) -> some View {
        modifier(BackupImportFlow(incoming: incoming))
    }
}

/// The planner compares the file with what is on the device,
/// `ImportBackupView` asks what to bring in and `BackupImporter` writes it —
/// all of it saved at once, or none. One way in, whether the file was picked
/// or came from the server.
private struct BackupImportFlow: ViewModifier {
    @Binding var incoming: IncomingBackup?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(filter: WorkoutSession.trained, sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(filter: WorkoutSession.templates, sort: \WorkoutSession.templateOrder) private var templates: [WorkoutSession]
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]

    /// The backup read, and what the planner made of it, while the import
    /// sheet is up.
    @State private var pending: (package: BackupPackage, plan: ImportPlan, source: IncomingBackup.Source)?
    @State private var showImportOptions = false
    @State private var importChoice: ImportChoice?
    @State private var alertMessage = ""
    /// Offered beside OK when only support can help with what failed.
    @State private var alertMail: URL?
    @State private var showAlert = false
    /// Set by an import: when its message closes, `backupImported` goes out.
    @State private var announceImport = false

    func body(content: Content) -> some View {
        content
            .onChange(of: incoming?.id) {
                guard let incoming else { return }
                self.incoming = nil
                read(incoming)
            }
            .sheet(isPresented: $showImportOptions, onDismiss: performImportIfChosen) {
                if let pending {
                    ImportBackupView(file: pending.package.file, missingPhotoCount: pending.package.missingPhotoCount, plan: pending.plan, choice: $importChoice)
                }
            }
            .onChange(of: showAlert) { _, isShown in
                guard !isShown, announceImport else { return }
                announceImport = false
                NotificationCenter.default.post(name: .backupImported, object: nil)
            }
            .alert("Backup", isPresented: $showAlert) {
                if let alertMail {
                    Button("Write to Support") {
                        // Without a mail app the link goes nowhere: the
                        // address is copied instead.
                        openURL(alertMail) { accepted in
                            guard !accepted else { return }
                            UIPasteboard.general.string = Support.address
                            report("No mail app is set up. The address \(Support.address) is copied; paste it into the mail app you use.")
                        }
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
    }

    private func report(_ message: String, mail: URL? = nil) {
        alertMessage = message
        alertMail = mail
        showAlert = true
    }

    private func read(_ incoming: IncomingBackup) {
        do {
            let package = try BackupPackage.read(from: incoming.data)
            let file = package.file
            guard !file.bringsNothing else {
                report("This backup does not contain anything to import.")
                return
            }
            let plan = ImportPlanner.plan(
                file: file,
                existing: definitions.map { ImportPlanner.Existing(id: $0.id, record: BackupExporter.record($0)) },
                knownWorkoutIDs: Set(sessions.map(\.id)),
                knownTemplateIDs: Set(templates.map(\.id))
            )
            pending = (package, plan, incoming.source)
            showImportOptions = true
        } catch let refused as BackupReadError {
            report(refused.localizedDescription, mail: refused.supportMail)
        } catch {
            report("Import failed: \(error.localizedDescription)")
        }
    }

    private func performImportIfChosen() {
        guard let pending, let choice = importChoice else {
            self.pending = nil
            return
        }
        self.pending = nil
        importChoice = nil

        let summary = BackupImporter(context: modelContext)
            .apply(pending.plan, decisions: choice.decisions, selection: choice.selection, photos: pending.package.photos)

        // Nothing is half-imported: "Replace All" has already deleted every
        // workout in the context by this point, so leaving the failed changes
        // pending would show an emptied history the store does not actually
        // hold — and hand the next successful save somewhere else in the app a
        // deletion nobody asked for.
        if let failure = modelContext.save(reporting: "Import failed while saving.") {
            modelContext.rollback()
            report(failure)
            return
        }
        // What came in is brought in line with the catalog now rather than
        // at the next launch: which own exercises are catalog ones, and
        // which entries belong to the one-sided form of their exercise. An
        // undecided own exercise never used goes before the assistant can
        // ask about it.
        try? CatalogSync.run(in: modelContext)
        try? SidesSettlement.dropLeftovers(in: modelContext)
        // A day variant from the file whose week is over goes now, not
        // a moment after it showed first on the shelf.
        if DayVariants.putAwayExpired(
            in: modelContext,
            deleting: UserDefaults.standard.bool(forKey: SettingsKey.deleteUnusedDayVariants)
        ) {
            try? modelContext.save()
        }
        // The server's backup is in: this device holds what it held and
        // writes over it from now on — at once, so the server has both.
        if case .server(let etag) = pending.source {
            SyncCenter.shared.adoptServerBackup(etag: etag)
            SyncCenter.shared.syncInBackground(.automatic, in: modelContext)
        }
        announceImport = true
        report(summary.message)
    }
}
