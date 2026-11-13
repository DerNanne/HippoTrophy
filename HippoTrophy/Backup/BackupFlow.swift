import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension View {
    /// Adds the "Backup" menu to the toolbar and everything behind it: the
    /// export choice and file dialog, the import file dialog, the import from
    /// the sync server, the import review and the message at the end. The
    /// view this is attached to needs nothing else for it.
    func backupFlow() -> some View {
        modifier(BackupFlow())
    }
}

/// Export and import from the start screen, in one place.
///
/// Export: pick what to include, then save the file. Import: pick a file, or
/// fetch the backup from the sync server; `backupImport` takes it from there.
private struct BackupFlow: ViewModifier {
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
    @State private var incoming: IncomingBackup?
    @State private var isDownloading = false
    @State private var alertMessage = ""
    @State private var showAlert = false

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
                        if SyncCenter.shared.isOn {
                            Button("Import from Server") {
                                Task { await importFromServer() }
                            }
                            .disabled(isDownloading)
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
                readFile(result)
            }
            .alert("Backup", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .backupImport($incoming)
    }

    private func report(_ message: String) {
        alertMessage = message
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

    private func readFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            // Read whole, not mapped: the file is planned after the access
            // to it has ended.
            incoming = IncomingBackup(data: try Data(contentsOf: url), source: .file)
        } catch {
            report("Import failed: \(error.localizedDescription)")
        }
    }

    private func importFromServer() async {
        isDownloading = true
        defer { isDownloading = false }
        switch await SyncCenter.shared.downloadBackup() {
        case .success(let backup):
            incoming = IncomingBackup(data: backup.data, source: .server(etag: backup.etag))
        case .failure(let problem):
            report("⚠️ \(problem.localizedDescription)")
        }
    }
}
