import SwiftUI
import UIKit
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted once the message after an import is closed: what came in may
    /// hold exercises the sides assistant has to ask about, and it asks
    /// before anything else, not only at the next launch.
    static let backupImported = Notification.Name("HippoTrophy.backupImported")
}

extension View {
    /// Adds the "Backup" menu to the toolbar and everything behind it: the
    /// export choice and file dialog, the import file dialog, the import review
    /// and the message at the end. The view this is attached to needs nothing
    /// else for it.
    func backupFlow() -> some View {
        modifier(BackupFlow())
    }
}

/// Export and import from the start screen, in one place.
///
/// Export: pick what to include, then save the file. Import: pick a file, the
/// planner compares it with what is on the device, `ImportBackupView` asks
/// what to bring in, and `BackupImporter` writes it — all of it saved at once,
/// or none.
private struct BackupFlow: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: WorkoutSession.trained, sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(filter: WorkoutSession.templates, sort: \WorkoutSession.templateOrder) private var templates: [WorkoutSession]
    @Query(sort: \ExerciseDefinition.orderIndex) private var definitions: [ExerciseDefinition]
    @Query private var gyms: [Gym]
    @Query private var machines: [Machine]

    @State private var showExportOptions = false
    @State private var exportSelection: BackupSelection?
    @State private var exportDocument: BackupFileDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    /// The file just picked, and what the planner made of it, while the
    /// import sheet is up.
    @State private var pendingImport: (package: BackupPackage, plan: ImportPlan)?
    @State private var showImportOptions = false
    @State private var importChoice: ImportChoice?
    @State private var alertMessage = ""
    /// Offered beside OK when only support can help with what failed.
    @State private var alertMail: URL?
    @State private var showAlert = false
    /// Set by an import: when its message closes, `backupImported` goes out.
    @State private var announceImport = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Backup") {
                        Button("Export Backup") {
                            showExportOptions = true
                        }
                        Button("Import Backup") {
                            showImporter = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showExportOptions, onDismiss: startExportIfSelected) {
                ExportBackupView(
                    exerciseCount: definitions.filter { !$0.isCatalog }.count,
                    workoutCount: sessions.count,
                    templateCount: templates.count,
                    exercisePhotos: definitions.compactMap(\.ownPhoto).map(\.data.count),
                    machinePhotos: machines.compactMap(\.photo).map(\.data.count),
                    selection: $exportSelection
                )
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: exportDocument?.contentType ?? .json,
                defaultFilename: BackupFileDocument.defaultFilename()
            ) { result in
                switch result {
                case .success:
                    report("Backup saved.")
                case .failure(let error):
                    report("Export failed: \(error.localizedDescription)")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: BackupFileDocument.readableContentTypes) { result in
                readBackup(result)
            }
            .sheet(isPresented: $showImportOptions, onDismiss: performImportIfChosen) {
                if let pending = pendingImport {
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

    private func startExportIfSelected() {
        guard let selection = exportSelection else { return }
        exportSelection = nil
        exportDocument = BackupFileDocument(
            package: BackupExporter.package(
                definitions: selection.exercises ? definitions : nil,
                sessions: selection.workouts ? sessions : nil,
                templates: selection.templates ? templates : nil,
                // The lists that workouts and templates pick from, always
                // along: small, and a file without them would bring the names
                // but not which machine stands in which gym.
                gyms: gyms,
                machines: machines,
                includingPhotos: selection.photos
            )
        )
        showExporter = true
    }

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let package = try BackupPackage.read(from: try Data(contentsOf: url, options: .mappedIfSafe))
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
            pendingImport = (package, plan)
            showImportOptions = true
        } catch let refused as BackupReadError {
            report(refused.localizedDescription, mail: refused.supportMail)
        } catch {
            report("Import failed: \(error.localizedDescription)")
        }
    }

    private func performImportIfChosen() {
        guard let pending = pendingImport, let choice = importChoice else {
            pendingImport = nil
            return
        }
        pendingImport = nil
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
        announceImport = true
        report(summary.message)
    }
}
