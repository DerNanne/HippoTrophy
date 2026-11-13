import Foundation

/// What went wrong, in the words the settings show. Every failure of a sync
/// ends up as one of these, so the message does not depend on which request
/// happened to fail.
nonisolated enum SyncProblem: Error, Equatable {
    /// No network, or the server did not answer.
    case unreachable
    /// The server's certificate is not one the iPhone trusts.
    case certificate
    /// User or password refused.
    case credentials
    /// The address leads somewhere, but not into a WebDAV folder.
    case notAFolder
    /// Another device wrote the backup on the server since this one did.
    case foreignBackup
    /// Asked to bring the backup in from a server that has none.
    case noBackupOnServer
    case address(SyncLayout.AddressProblem)
    case server(Int)
    case other(String)

    static func from(_ error: Error) -> SyncProblem {
        if let problem = error as? SyncProblem { return problem }
        if let problem = error as? SyncLayout.AddressProblem { return .address(problem) }
        if let webDAV = error as? WebDAVError {
            switch webDAV {
            case .status(401), .status(403): return .credentials
            case .status(404), .status(405), .status(409), .unreadableAnswer: return .notAFolder
            case .status(let code): return .server(code)
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .clientCertificateRejected, .secureConnectionFailed:
                return .certificate
            case .userAuthenticationRequired:
                return .credentials
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return .unreachable
            default:
                return .other(url.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }

    /// Whether trying again later can fix it without anyone doing anything.
    var isTemporary: Bool {
        switch self {
        case .unreachable, .server: true
        default: false
        }
    }
}

extension SyncProblem: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreachable:
            "The server could not be reached. The app tries again the next time it opens."
        case .certificate:
            "The server's certificate is not trusted by this iPhone. If you made it yourself, install your certificate authority as a profile and turn it on under Settings → General → About → Certificate Trust Settings. The FAQ explains how."
        case .credentials:
            "The server did not accept the user name or password. With Nextcloud, use an app password."
        case .notAFolder:
            "The address does not lead to a WebDAV folder you can write to. Check it in your server's web interface; with Nextcloud it ends in /remote.php/dav/files/ and your user name."
        case .foreignBackup:
            "The backup on the server was written by another device, or before this iPhone was connected. Sync waits until you decide which one counts."
        case .noBackupOnServer:
            "There is no backup on the server yet. It gets one the first time a device connected to it uploads."
        case .address(let problem):
            problem.localizedDescription
        case .server(let code):
            "The server answered with error \(code). The app tries again the next time it opens."
        case .other(let text):
            text
        }
    }
}
