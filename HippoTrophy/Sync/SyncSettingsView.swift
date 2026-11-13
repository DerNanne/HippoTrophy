import SwiftUI
import SwiftData

/// Settings → Sync: connecting a WebDAV server of the user's own, what the
/// last upload did, and turning it off again.
struct SyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    private let center = SyncCenter.shared

    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var connectProblem: SyncProblem?
    /// What Sync Now came to, until the next run.
    @State private var syncNote: String?
    @State private var confirmReplace = false
    @State private var confirmTurnOff = false

    var body: some View {
        List {
            if let connection = center.connection {
                connected(connection)
            } else {
                setup
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Not connected

    @ViewBuilder private var setup: some View {
        Section {
            TextField("https://cloud.example.com/remote.php/dav/files/alex/", text: $address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("User Name", text: $user)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
        } header: {
            Text("Your WebDAV Server")
        } footer: {
            Text("Sync puts a backup of everything on a server of your own — a Nextcloud, or a small WebDAV server in Docker — when you finish a workout and when you leave the app after a change. It goes nowhere else. The app makes a folder called HippoTrophy at this address and writes only there. HTTPS only; the FAQ explains how to use a certificate of your own.")
        }

        Section {
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Text("Connect")
                    if isConnecting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isConnecting || address.isEmpty || user.isEmpty || password.isEmpty)
        } footer: {
            if let connectProblem {
                warning(connectProblem.localizedDescription)
            }
        }
    }

    private func connect() async {
        isConnecting = true
        connectProblem = nil
        let problem = await center.connect(address: address, user: user, password: password)
        isConnecting = false
        guard problem == nil else {
            connectProblem = problem
            return
        }
        password = ""
        if !center.state.foreignBackupOnServer {
            await run(.manual)
        }
    }

    // MARK: - Connected

    @ViewBuilder private func connected(_ connection: SyncCenter.Connection) -> some View {
        Section {
            LabeledContent("Folder", value: connection.layout.folder.absoluteString)
            LabeledContent("User Name", value: connection.user)
        } header: {
            Text("Your WebDAV Server")
        }

        if center.state.foreignBackupOnServer {
            Section {
                warning(SyncProblem.foreignBackup.localizedDescription)
                Button("Replace It with This iPhone's Data", role: .destructive) {
                    confirmReplace = true
                }
                .confirmationDialog("Replace the backup on the server?", isPresented: $confirmReplace, titleVisibility: .visible) {
                    Button("Replace", role: .destructive) {
                        Task { await run(.replaceServer) }
                    }
                } message: {
                    Text("The backup on the server is written over with what is on this iPhone. The copies in history/ stay.")
                }
            } header: {
                Text("Another Backup on the Server")
            } footer: {
                Text("To bring that backup onto this iPhone instead, download backup.zip from your server and pick it under Backup → Import Backup.")
            }
        }

        Section {
            LabeledContent("Last Upload") {
                if let date = center.state.lastUpload {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                }
            }
            if let error = center.state.lastError {
                warning(error)
            }
            Button {
                Task { await run(.manual) }
            } label: {
                HStack {
                    Text("Sync Now")
                    if center.isSyncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(center.isSyncing || center.state.foreignBackupOnServer)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let syncNote {
                    Text(syncNote)
                }
                Text("The app uploads when you finish a workout and when you leave it after a change, never while a workout is running. On the server are backup.zip, the newest, and in history/ a copy for each of the last 14 days you trained or changed something.")
            }
        }

        Section {
            Button("Turn Off Sync", role: .destructive) {
                confirmTurnOff = true
            }
            .confirmationDialog("Turn off sync?", isPresented: $confirmTurnOff, titleVisibility: .visible) {
                Button("Turn Off", role: .destructive) {
                    center.disconnect()
                    syncNote = nil
                }
            } message: {
                Text("The address and password are removed from this iPhone. What is on the server stays there.")
            }
        }
    }

    private func run(_ trigger: SyncTrigger) async {
        syncNote = nil
        switch await center.sync(trigger, in: modelContext) {
        case .uploaded: syncNote = "Uploaded."
        case .unchanged: syncNote = nil
        case .workoutRunning: syncNote = "A workout is running. The app uploads once it is finished."
        case .waitingForDecision, .failed, .off: syncNote = nil
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
    }
}

#Preview {
    NavigationStack {
        SyncSettingsView()
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
