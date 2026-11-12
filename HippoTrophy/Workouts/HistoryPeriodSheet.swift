import SwiftUI

/// Picks the start and end of a custom history range. The end is prefilled with
/// today, which is the range a workout log is asked about most of the time, and
/// only needs touching to look at a closed stretch in the past.
struct HistoryPeriodSheet: View {
    /// Prefills the fields; `nil` when no custom range has been set yet.
    let currentStart: Date?
    /// `nil` stands for "up to today", which is also the default.
    let currentEnd: Date?
    /// The oldest logged workout, so the fields cannot wander past the data.
    let earliestSessionDate: Date?
    /// Called with the chosen days once the sheet is confirmed.
    let onApply: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var editingStart = false
    @State private var editingEnd = false

    private let calendar = Calendar.current

    private var today: Date {
        calendar.startOfDay(for: .now)
    }

    private var earliestSelectable: Date {
        guard let earliestSessionDate else { return today }
        return min(calendar.startOfDay(for: earliestSessionDate), today)
    }

    // Both ranges are clamped rather than derived straight from the other
    // field: a momentarily inverted pair would otherwise build an invalid
    // `ClosedRange` and trap before `onChange` can straighten it out.
    private var startRange: ClosedRange<Date> {
        earliestSelectable...max(earliestSelectable, min(end, today))
    }

    private var endRange: ClosedRange<Date> {
        min(max(start, earliestSelectable), today)...today
    }

    private var summary: String {
        let from = start.formatted(date: .long, time: .omitted)
        if calendar.isDateInToday(end) {
            return "Shows workouts from \(from) up to today."
        }
        return "Shows workouts from \(from) to \(end.formatted(date: .long, time: .omitted))."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    dateRow(
                        title: "From",
                        date: $start,
                        range: startRange,
                        marksToday: false,
                        isEditing: $editingStart
                    )
                    dateRow(
                        title: "To",
                        date: $end,
                        range: endRange,
                        marksToday: calendar.isDateInToday(end),
                        isEditing: $editingEnd
                    )
                } footer: {
                    Text(summary)
                }

                if !calendar.isDateInToday(end) {
                    Section {
                        Button("End Today") {
                            end = today
                        }
                    }
                }
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(start, end)
                        dismiss()
                    }
                }
            }
            .onAppear {
                end = clamped(currentEnd ?? today)
                start = clamped(currentStart ?? earliestSelectable, notAfter: end)
            }
            // Dragging one end past the other pulls the other along, so the
            // range never has to be rejected.
            .onChange(of: start) { _, newValue in
                if newValue > end { end = min(newValue, today) }
            }
            .onChange(of: end) { _, newValue in
                if newValue < start { start = max(newValue, earliestSelectable) }
            }
        }
    }

    /// A date field built by hand instead of a `DatePicker`. The picker's own
    /// chip is a translucent fill that cannot take a second word, and stacking
    /// one behind it darkens the overlap into a visible seam — so the row owns
    /// its chip and opens the calendar itself.
    private func dateRow(
        title: String,
        date: Binding<Date>,
        range: ClosedRange<Date>,
        marksToday: Bool,
        isEditing: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Button {
                isEditing.wrappedValue = true
            } label: {
                HStack(spacing: 6) {
                    // The calendar only ever shows a date, so an open-ended
                    // range needs the word to say so.
                    if marksToday {
                        Text("Today")
                    }
                    Text(date.wrappedValue.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: isEditing) {
                DatePicker(title, selection: date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 320, height: 350)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func clamped(_ date: Date, notAfter upperBound: Date? = nil) -> Date {
        let day = calendar.startOfDay(for: date)
        return min(max(day, earliestSelectable), upperBound ?? today)
    }
}
