import SwiftUI

/// One set in the editor: a cell per field of the exercise, then the set's
/// controls, its effort and its tick. Cells wrap three to a row, so an
/// exercise with many fields stays readable. The effort is rated on the
/// entry's scale and left out when the entry rates nothing. A template's
/// sets are a plan by nature and have no tick.
struct SetRowView: View {
    @Bindable var setEntry: SetEntry
    /// Copy and delete only make sense among several sets; an exercise that
    /// logs once per workout shows neither.
    var showsSetControls: Bool
    var onDelete: () -> Void
    var onCopy: () -> Void
    var onEffortChange: () -> Void
    @AppStorage(SettingsKey.weightUnit) private var weightUnitRaw = WeightUnit.kilograms.rawValue
    @Environment(\.setTicked) private var setTicked
    @Environment(\.setSideTicked) private var setSideTicked
    private let restTimer = RestTimerCenter.shared
    private let oneSideTicks = OneSideTicks.shared
    @State private var showEffortPicker = false

    private static let cellsPerRow = 3

    private var unit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kilograms
    }

    private var effortScale: EffortScale {
        setEntry.exercise?.effortScale ?? .off
    }

    private var showsTick: Bool {
        setEntry.exercise?.session?.isTemplate != true
    }

    private var rows: [[FieldValue]] {
        let values = setEntry.sortedValues
        return stride(from: 0, to: values.count, by: Self.cellsPerRow).map { start in
            Array(values[start..<min(start + Self.cellsPerRow, values.count)])
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            fields
            // The rest that follows this set, where the next one is read.
            if let timer = restTimer.timer, timer.setID == setEntry.id {
                RestInlineBar(timer: timer)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: restTimer.timer?.setID == setEntry.id)
    }

    private var fields: some View {
        // Three cells, two buttons and the effort have to share one row on
        // the narrowest phone, so nothing here is generous with its width.
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(row) { value in
                            ValueCell(value: value, unit: unit)
                        }
                    }
                }
            }

            if showsSetControls {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            if effortScale != .off {
                Button {
                    showEffortPicker = true
                } label: {
                    // The gauge's weight sits in its bottom bars, the badge's
                    // in its middle; the badge goes a little lower so both
                    // line up with the copy and delete buttons.
                    EffortIndicator(scale: effortScale, effort: setEntry.effort)
                        .padding(.top, effortScale == .rir ? 11 : 8)
                        .padding(.bottom, effortScale == .rir ? 5 : 8)
                        .padding(.horizontal, 4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEffortPicker, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    EffortPicker(scale: effortScale, effort: setEntry.effort) { effort in
                        setEntry.effort = effort
                        onEffortChange()
                        showEffortPicker = false
                    } onStep: { effort in
                        setEntry.effort = effort
                        onEffortChange()
                    }
                    .padding(12)
                    // Without this a popover on iPhone turns into a sheet over
                    // the whole screen, which is far more than a few icons are
                    // worth.
                    .presentationCompactAdaptation(.popover)
                }
            }

            Spacer(minLength: 0)

            if showsTick {
                tick
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var tickMode: UnilateralMode {
        setEntry.exercise?.unilateralMode ?? .bilateral
    }

    private var tickState: SetTick {
        SetTick(isDone: setEntry.isDone, oneSideDone: oneSideTicks.contains(setEntry.id), mode: tickMode)
    }

    private var tick: some View {
        Button {
            let next = tickState.tapped(mode: tickMode)
            oneSideTicks.set(setEntry.id, oneSideDone: next == .oneSideDone)
            setEntry.isDone = next == .done
            switch next {
            case .open: break
            case .oneSideDone: setSideTicked(setEntry)
            case .done: setTicked(setEntry)
            }
        } label: {
            Image(systemName: tickSymbol)
                .font(.title2)
                .foregroundStyle(tickState == .open ? Color.secondary : Color.green)
                .padding(.top, 6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: tickState)
        .accessibilityLabel(tickWords)
        .accessibilityHint(tickMode == .oneSided ? "Ticks off one side, then the other, or takes the tick out" : "Ticks the set off, or takes the tick out")
    }

    private var tickSymbol: String {
        switch tickState {
        case .open: return "circle"
        case .oneSideDone: return setEntry.exercise?.startSide == .right ? "circle.righthalf.filled" : "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var tickWords: String {
        switch tickState {
        case .open: return "Not done"
        case .oneSideDone: return "One side done"
        case .done: return "Done"
        }
    }

    private var accessibilityText: String {
        let values = setEntry.sortedValues.map { value in
            value.type.fieldType == .weight
                ? "\(value.label) \(value.editText(unit: unit)) \(unit.spokenName)"
                : "\(value.label) \(value.displayText(unit: unit))"
        }
        let prefix = showsSetControls ? "Set \(setEntry.setNumber), " : ""
        let effort = effortScale == .off ? "" : ", " + (setEntry.effort?.label ?? "Effort not rated")
        let done = showsTick ? ", " + tickWords.lowercased() : ""
        return prefix + values.joined(separator: ", ") + effort + done
    }

}

/// One labelled value of a set. It holds the text the user typed and writes
/// the canonical form to the model; what cannot be read as the field's value
/// is refused, and a mark behind a number goes when the field is left.
///
/// A duration is the exception: three wheels cannot live in a cell, so the
/// cell shows the value and opens a picker instead of taking keystrokes.
private struct ValueCell: View {
    @Bindable var value: FieldValue
    let unit: WeightUnit
    @Environment(\.setFieldFocus) private var focus
    @State private var text: String
    @State private var showDurationPicker = false
    @FocusState private var isEditing: Bool

    private static let width: CGFloat = 66

    init(value: FieldValue, unit: WeightUnit) {
        _value = Bindable(wrappedValue: value)
        self.unit = unit
        _text = State(initialValue: value.editText(unit: unit))
    }

    var body: some View {
        VStack(spacing: 4) {
            if value.type == .time {
                durationField
            } else {
                textField
            }

            Text(value.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.label)
    }

    private var textField: some View {
        TextField(value.type.placeholder, text: $text)
            .keyboardType(value.type.keyboardType)
            .multilineTextAlignment(.center)
            .frame(width: Self.width, height: 38)
            .background { cellBorder }
            .modifier(FocusedAs(id: value.id, focus: focus))
            .focused($isEditing)
            .onChange(of: isEditing) { _, editing in
                if !editing { text = value.type.settledInput(text) }
            }
            .onChange(of: text) { oldValue, newValue in
                let accepted = value.type.acceptedInput(newValue, replacing: oldValue)
                // Setting the text brings this back with what was accepted.
                guard accepted == newValue else {
                    text = accepted
                    return
                }
                value.applyInput(newValue, unit: unit)
            }
            // Keeps the field in step with a value changed elsewhere — copying
            // a set, switching the unit — without disturbing what is typed.
            .onChange(of: value.numberValue) { _, _ in
                sync()
            }
            .onChange(of: unit) { _, _ in
                text = value.editText(unit: unit)
            }
    }

    private func sync() {
        let shown = value.editText(unit: unit)
        guard shown != text else { return }
        if value.type.fieldType == .weight, let stored = value.numberValue,
           let typed = FieldType.number(fromInput: text).map(unit.kilograms(from:)),
           abs(typed - stored) <= unit.storageTolerance {
            return
        }
        text = shown
    }

    private var durationField: some View {
        Button {
            showDurationPicker = true
        } label: {
            Text(value.durationSeconds.map { DurationFormat.text(forSeconds: $0) }
                 ?? value.type.placeholder)
                .foregroundStyle(value.durationSeconds == nil ? .tertiary : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.width, height: 38)
                .background { cellBorder }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDurationPicker) {
            DurationPickerSheet(
                title: value.label.isEmpty ? "Duration" : value.label,
                totalSeconds: $value.durationSeconds
            )
            .presentationDetents([.height(380)])
        }
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color(.separator), lineWidth: 1)
    }
}

/// Ties a set's field to the editor's focus, when the editor hands one
/// down: Next and the end of a rest move the cursor through it.
private struct FocusedAs: ViewModifier {
    let id: UUID
    let focus: FocusState<UUID?>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus, equals: id)
        } else {
            content
        }
    }
}

/// The row of the set to do next: the accent over the card, stronger than a
/// superset's B, with a bar on the leading edge like a superset's rows.
struct GuideHighlight: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Color(.secondarySystemGroupedBackground)
            Color.accentColor.opacity(0.18)
            Color.accentColor.frame(width: 4)
        }
    }
}
