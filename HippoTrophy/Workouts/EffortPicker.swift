import SwiftUI

/// What opens behind a set's effort: the ratings its entry's scale offers, and
/// a way to take the rating back off. Easy, normal and hard are three taps;
/// reps in reserve are a tap per band and a stepper for any value in between.
struct EffortPicker: View {
    let scale: EffortScale
    let effort: SetEffort?
    /// A choice that settles it — an option or Clear. The caller closes the
    /// picker.
    var onPick: (SetEffort?) -> Void
    /// A step to an exact value. The picker stays open for the next one.
    var onStep: (SetEffort) -> Void

    var body: some View {
        switch scale {
        case .off:
            EmptyView()
        case .levels:
            HStack(alignment: .top, spacing: 16) {
                ForEach(scale.choices, id: \.self) { choice in
                    levelOption(choice)
                }
                clearButton(vertical: true)
            }
        case .rir:
            rirPicker
        }
    }

    private func levelOption(_ choice: SetEffort) -> some View {
        Button {
            onPick(choice)
        } label: {
            VStack(spacing: 4) {
                EffortIndicator(scale: .levels, effort: choice, size: 24)
                Text(choice.label)
                    .font(.caption)
                    .foregroundStyle(choice == effort ? Color.primary : Color.secondary)
            }
            .padding(4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
    }

    private var rir: Double? {
        if case .rir(let value) = effort { return value }
        return nil
    }

    private var rirPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reps in Reserve")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(RIRBand.allCases, id: \.self) { band in
                    Button {
                        onPick(.rir(band.preset))
                    } label: {
                        RIRBadge(rir: band.preset, label: band.presetLabel, size: 28)
                            .padding(3)
                            .overlay {
                                // The band's own preset, when that is the
                                // value — a stepped value has no button.
                                if rir == band.preset {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(Color.primary, lineWidth: 2)
                                }
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(band.presetLabel) reps in reserve")
                    .accessibilityHint(band.meaning)
                }
            }

            Text(rir.map { RIRBand.containing($0).meaning } ?? "How many more reps were left?")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Stepper(value: stepBinding, in: EffortScale.rirRange, step: EffortScale.rirStep) {
                    Text(rir.map { "RIR \(RIRBand.format($0))" } ?? "RIR –")
                        .font(.subheadline.monospacedDigit())
                }
                .fixedSize()
                .accessibilityLabel("Exact Reps in Reserve")
                Spacer(minLength: 0)
                clearButton(vertical: false)
            }
        }
        .fixedSize()
    }

    /// Stepping starts from 0 when nothing is rated yet: the first step up
    /// logs a half, and there is no step down from nothing.
    private var stepBinding: Binding<Double> {
        Binding(
            get: { rir ?? EffortScale.rirRange.lowerBound },
            set: { onStep(.rir($0)) }
        )
    }

    /// Takes the rating back off, for a set rated by mistake or one that is
    /// not worth rating — a warm-up.
    private func clearButton(vertical: Bool) -> some View {
        Button {
            onPick(nil)
        } label: {
            Group {
                if vertical {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 20))
                            .frame(height: 24)
                        Text("Clear")
                            .font(.caption)
                    }
                    .padding(4)
                } else {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(effort == nil)
        .accessibilityLabel("Clear Effort")
    }
}
