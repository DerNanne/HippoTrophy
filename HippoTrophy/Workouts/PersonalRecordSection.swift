import SwiftUI

/// The personal record at the top of an exercise's history: the set and the
/// day. `ExerciseProgress.records` decides which set it is. Nothing shows for
/// a history without an unassisted lift.
struct PersonalRecordSection: View {
    let records: [ExerciseProgress.Record]
    let unit: WeightUnit

    var body: some View {
        if !records.isEmpty {
            Section {
                ForEach(records, id: \.id) { record in
                    row(record)
                }
            }
        }
    }

    private func row(_ record: ExerciseProgress.Record) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("PR")
                .fontWeight(.semibold)
            PersonalRecordIcon()
            // A side's record says which side; otherwise, with a shared
            // weight and one side's each having a record, the badge tells
            // them apart.
            if record.side != .both {
                Text(record.side == .left ? "Left" : "Right")
                    .foregroundStyle(.secondary)
            } else if records.count > 1 {
                UnilateralModeBadge(mode: record.mode)
            }
            Spacer(minLength: 8)
            Text(record.setText(unit: unit))
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(record.date.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
