import SwiftUI
import UIKit

/// Where users write when the app cannot help itself — an old backup to
/// convert, say.
nonisolated enum Support {
    static let address = "hippotrophy@gmail.com"

    static func mail(subject: String, body: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
            + (body.map { [URLQueryItem(name: "body", value: $0)] } ?? [])
        return components.url
    }
}

/// A button that writes to support. Without a mail app the link goes
/// nowhere, so the address is copied instead and the button says so.
struct SupportMailButton: View {
    let subject: String
    /// Prefilled text of the mail, if any.
    var message: String? = nil
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        Button("Write to \(Support.address)", systemImage: "envelope") {
            guard let mail = Support.mail(subject: subject, body: message) else { return copy() }
            openURL(mail) { accepted in
                if !accepted { copy() }
            }
        }
        .alert("No Mail App", isPresented: $copied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The address \(Support.address) is copied. Paste it into the mail app you use.")
        }
    }

    private func copy() {
        UIPasteboard.general.string = Support.address
        copied = true
    }
}
