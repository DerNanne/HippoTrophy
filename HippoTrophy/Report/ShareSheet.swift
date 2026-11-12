import SwiftUI
import UIKit

/// A file handed to the system share sheet. `URL` is not `Identifiable`, and the
/// identity has to be fresh per share anyway: sharing the same workout twice
/// should reopen the sheet, not be swallowed as an unchanged value.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet. SwiftUI's `ShareLink` wants its item before the tap;
/// the report is rendered on the tap, so the sheet is presented directly.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
