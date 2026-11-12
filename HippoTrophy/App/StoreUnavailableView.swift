import SwiftUI

/// What the app shows instead of crashing when its store will not open — after
/// a migration that fails, or when an older build finds a store a newer one
/// wrote. The data is untouched either way, and the one thing that would lose
/// it is deleting the app, which is what someone does with an app that dies
/// on every launch. So: a warning, not an error, and no button that deletes.
struct StoreUnavailableView: View {
    let error: any Error

    private var technicalDetail: String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Your workouts couldn't be opened.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        } description: {
            Text("Nothing has been changed or deleted. Deleting the app would delete your data too, so check for an update first.")
        } actions: {
            // For a bug report: selectable, so it can be copied as it is.
            Text(technicalDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    StoreUnavailableView(error: NSError(domain: NSCocoaErrorDomain, code: 134504))
}
