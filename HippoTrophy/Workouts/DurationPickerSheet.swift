import SwiftUI

/// Sets a duration on three wheels, the way the Clock app sets a timer. Picking
/// instead of typing is what makes an invalid duration impossible to enter.
struct DurationPickerSheet: View {
    let title: String
    /// Whole seconds as logged on the value; nil means nothing logged yet.
    @Binding var totalSeconds: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // A wheel wants its own 216pt; pinning the row keeps the numbers
                // centred instead of letting the stack squash them.
                wheels
                    .frame(height: 216)

                Spacer(minLength: 0)

                Button("Clear") {
                    totalSeconds = nil
                    dismiss()
                }
                .padding(.bottom, 12)
                .disabled(totalSeconds == nil)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        totalSeconds = DurationFormat.clampedSeconds(
                            hours: hours,
                            minutes: minutes,
                            seconds: seconds
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                let parts = DurationFormat.components(fromSeconds: totalSeconds ?? 0)
                hours = parts.hours
                minutes = parts.minutes
                seconds = parts.seconds
            }
        }
    }

    private var wheels: some View {
        HStack(spacing: 0) {
            wheel(selection: $hours, range: 0..<24, unit: "hours")
            wheel(selection: $minutes, range: 0..<60, unit: "min")
            wheel(selection: $seconds, range: 0..<60, unit: "sec")
        }
    }

    private func wheel(selection: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        // The unit sits beside the wheel rather than inside a row, so the numbers
        // stay centred while scrolling — the same arrangement the Clock app uses.
        HStack(spacing: 2) {
            Picker("", selection: selection) {
                ForEach(range, id: \.self) { number in
                    Text("\(number)")
                        .monospacedDigit()
                        .tag(number)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 64)
            .clipped()

            Text(unit)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(unit)
    }
}

#Preview {
    @Previewable @State var value: Int? = 510
    return Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            DurationPickerSheet(title: "Duration", totalSeconds: $value)
                .presentationDetents([.height(320)])
        }
}
