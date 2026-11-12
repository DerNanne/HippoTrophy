import SwiftUI

/// What the export offers before anything is rendered: what the report will
/// contain, what it leaves out, and that it is still finding its shape.
///
/// The PDF is built only once Export is tapped. Rendering on the way in would
/// mean every glance at this screen paid for a document nobody asked for.
struct WorkoutExportSheet: View {
    let session: WorkoutSession
    /// Set on Export, left false on Cancel; read by the caller once dismissed.
    @Binding var confirmed: Bool
    /// The unit this one report prints in. Starts at the app's setting and is
    /// only for the export: a coach who works in pounds can be sent pounds
    /// without the whole app changing units.
    @Binding var unit: WeightUnit

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The report's own reading of the workout, so this sheet promises what
        // the PDF will hold. Cheap: it is values, not the rendered pages.
        let report = WorkoutReportData(session: session, unit: unit)
        NavigationStack {
            List {
                Section {
                    BetaWarningRow()
                }

                Section {
                    LabeledContent("Exercises", value: "\(report.exerciseCount)")
                    LabeledContent("Sets", value: "\(report.setCount)")
                } footer: {
                    Text("A printable report of this workout — sets, weights, reps and effort — as a PDF you can send to a coach. Longer workouts run onto further pages.")
                }

                // Named rather than counted: knowing *which* exercise is missing
                // is what lets someone decide whether the report is still worth
                // sending.
                if !report.skippedNames.isEmpty {
                    Section {
                        ForEach(report.skippedNames, id: \.self) { name in
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        // The same warning mark as the beta banner, so the two
                        // things this sheet is admitting to read as one kind.
                        Label {
                            Text("Not Included")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                    } footer: {
                        Text("Exercises without weight and reps are left out of the report for now, because their fields differ from one exercise to the next. The report says so on its last page.")
                    }
                }

                Section {
                    Picker("Weight Unit", selection: $unit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                } footer: {
                    Text("Only this report is affected — the app keeps the unit set in Settings.")
                }

                Section {
                    Button("Export PDF") {
                        confirmed = true
                        dismiss()
                    }
                } footer: {
                    Text("Exporting only reads your workout — nothing here changes your data.")
                }
            }
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        confirmed = false
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The banner at the top of the export sheet. Loud on purpose: someone about to
/// send this report to their coach should learn it is unfinished here, not from
/// the coach asking why half the workout is missing.
private struct BetaWarningRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("Beta feature")
                    .font(.subheadline.weight(.semibold))
                // Not `.secondary`: grey on the tinted row is legible in light
                // mode and washes out against the darker tint in dark mode.
                Text("The report is new and does not get everything right yet. Check it before you send it on.")
                    .font(.footnote)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.yellow.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beta feature. The report is new and does not get everything right yet. Check it before you send it on.")
    }
}
