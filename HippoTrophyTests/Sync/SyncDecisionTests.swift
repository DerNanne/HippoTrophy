import Foundation
import Testing
@testable import HippoTrophy

struct SyncDecisionTests {
    private let uploaded = SyncState(lastFingerprint: "same", lastETag: "\"1\"")

    @Test func uploadsOnlyWhatChangedOnItsOwn() {
        #expect(SyncDecision.before(trigger: .automatic, fingerprint: "same", state: uploaded, workoutRunning: false) == .unchanged)
        #expect(SyncDecision.before(trigger: .automatic, fingerprint: "new", state: uploaded, workoutRunning: false) == .upload)
    }

    @Test func uploadsOnSyncNowEvenUnchanged() {
        #expect(SyncDecision.before(trigger: .manual, fingerprint: "same", state: uploaded, workoutRunning: false) == .upload)
    }

    @Test func neverUploadsDuringAWorkout() {
        for trigger in [SyncTrigger.automatic, .manual, .replaceServer] {
            #expect(SyncDecision.before(trigger: trigger, fingerprint: "new", state: uploaded, workoutRunning: true) == .workoutRunning)
        }
    }

    @Test func waitsForTheUserOverAForeignBackup() {
        var state = uploaded
        state.foreignBackupOnServer = true
        #expect(SyncDecision.before(trigger: .automatic, fingerprint: "new", state: state, workoutRunning: false) == .waitingForDecision)
        #expect(SyncDecision.before(trigger: .manual, fingerprint: "new", state: state, workoutRunning: false) == .waitingForDecision)
        #expect(SyncDecision.before(trigger: .replaceServer, fingerprint: "same", state: state, workoutRunning: false) == .upload)
    }

    @Test func writesOverOnlyItsOwnBackup() {
        #expect(SyncDecision.serverIsOurs(currentETag: nil, knownETag: nil))
        #expect(SyncDecision.serverIsOurs(currentETag: nil, knownETag: "\"1\""))
        #expect(SyncDecision.serverIsOurs(currentETag: "\"1\"", knownETag: "\"1\""))
        #expect(!SyncDecision.serverIsOurs(currentETag: "\"2\"", knownETag: "\"1\""))
        #expect(!SyncDecision.serverIsOurs(currentETag: "\"1\"", knownETag: nil))
    }

    @Test func namesEveryFailureInWordsOfItsOwn() {
        #expect(SyncProblem.from(URLError(.serverCertificateUntrusted)) == .certificate)
        #expect(SyncProblem.from(URLError(.serverCertificateHasUnknownRoot)) == .certificate)
        #expect(SyncProblem.from(URLError(.notConnectedToInternet)) == .unreachable)
        #expect(SyncProblem.from(WebDAVError.status(401)) == .credentials)
        #expect(SyncProblem.from(WebDAVError.status(409)) == .notAFolder)
        #expect(SyncProblem.from(WebDAVError.status(507)) == .server(507))
        #expect(SyncProblem.unreachable.isTemporary)
        #expect(!SyncProblem.certificate.isTemporary)
    }
}

struct SyncUploadTests {
    private func package(at date: Date) -> BackupPackage {
        BackupPackage(file: BackupFile(
            exportedAt: date,
            workouts: [WorkoutRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Legs", date: date, notes: "", exercises: [])]
        ))
    }

    @Test func isAZipEvenWithoutPhotos() throws {
        let upload = try SyncUpload(package(at: .now))
        #expect(BackupZip.isZip(upload.data))
        let read = try BackupPackage.read(from: upload.data)
        #expect(read.file.workouts?.map(\.name) == ["Legs"])
        #expect(read.photos.isEmpty)
    }

    @Test func fingerprintIgnoresWhenTheBackupWasMade() throws {
        let earlier = try SyncUpload(package(at: Date(timeIntervalSinceReferenceDate: 1000)))
        var later = package(at: Date(timeIntervalSinceReferenceDate: 1000))
        later.file.exportedAt = Date(timeIntervalSinceReferenceDate: 9000)
        #expect(try SyncUpload(later).fingerprint == earlier.fingerprint)
        #expect(try SyncUpload(later).data != earlier.data)
    }

    @Test func fingerprintFollowsTheContent() throws {
        var changed = package(at: .now)
        changed.file.workouts?[0].name = "Legs and Core"
        #expect(try SyncUpload(changed).fingerprint != SyncUpload(package(at: .now)).fingerprint)
    }
}
