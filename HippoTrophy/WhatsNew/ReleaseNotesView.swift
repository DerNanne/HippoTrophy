import SwiftUI

/// Every build's notes, newest first, from Settings: the highlights the sheet
/// showed once, and the smaller changes it left out.
struct ReleaseNotesView: View {
    let notes: ReleaseNotes

    var body: some View {
        List {
            ForEach(notes.builds) { build in
                Section {
                    ForEach(build.highlights) { highlight in
                        HighlightRow(highlight: highlight)
                            .padding(.vertical, 6)
                    }
                    if !build.changes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(build.highlights.isEmpty ? "Changes" : "Also in This Build")
                                .font(.subheadline.weight(.semibold))
                            ForEach(build.changes, id: \.self) { change in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                    Text(change)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Build \(build.build)")
                }
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
    }
}
