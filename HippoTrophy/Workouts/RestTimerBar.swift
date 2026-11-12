import SwiftUI

/// The rest running, at the bottom of the workout editor: what is left beside
/// the whole rest, a bar that empties, and minus, plus and skip — which move
/// both numbers. The countdown runs on the system's clock, so the bar stays
/// right without a view ticking it.
struct RestTimerBar: View {
    let timer: RestTimer
    let onAdjust: (TimeInterval) -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onSkip: () -> Void

    private var interval: ClosedRange<Date> {
        let start = timer.endsAt.addingTimeInterval(-timer.duration)
        return start...max(timer.endsAt, start.addingTimeInterval(1))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(timer.isPaused ? "Paused" : timer.kind.title, systemImage: timer.isPaused ? "pause.circle" : timer.kind.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    if !timer.exerciseName.isEmpty {
                        Text(timer.exerciseName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Group {
                    if let paused = timer.pausedRemaining {
                        Text(DurationFormat.text(forSeconds: Int(paused.rounded(.up))))
                    } else {
                        Text(timerInterval: interval, countsDown: true)
                    }
                }
                .font(.title.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText(countsDown: true))
                Text("/ \(DurationFormat.text(forSeconds: timer.totalSeconds))")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("of \(DurationFormat.text(forSeconds: timer.totalSeconds))")
            }

            if timer.isPaused {
                ProgressView(value: timer.fractionLeft(at: .now))
            } else {
                ProgressView(timerInterval: interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }

            HStack(spacing: 10) {
                Button {
                    onAdjust(-RestTimer.step)
                } label: {
                    Text("−15 s").frame(maxWidth: .infinity)
                }
                .accessibilityLabel("15 seconds less")
                Button {
                    onAdjust(RestTimer.step)
                } label: {
                    Text("+15 s").frame(maxWidth: .infinity)
                }
                .accessibilityLabel("15 seconds more")
                Button(action: timer.isPaused ? onResume : onPause) {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(timer.isPaused ? "Resume" : "Pause")
                Button(action: onSkip) {
                    Text("Skip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
        }
        .tint(timer.kind.tint)
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(timer.kind == .betweenSides ? "Rest between sides" : "Rest timer")
    }
}

/// The rest under the set it follows, the way the set is read: a bar that
/// empties with what is left written across it. The controls stay at the
/// bottom, where the thumb is.
struct RestInlineBar: View {
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = timer.fractionLeft(at: context.date)
            Capsule()
                .fill(.tint.opacity(0.2))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * fraction)
                            .animation(.linear(duration: 1), value: fraction)
                    }
                }
                .overlay {
                    Label {
                        Text((timer.kind == .betweenSides ? "Other Side  " : "") + DurationFormat.text(forSeconds: Int(timer.remaining(at: context.date).rounded(.up))))
                    } icon: {
                        if timer.isPaused {
                            Image(systemName: "pause.fill")
                        } else if timer.kind == .betweenSides {
                            Image(systemName: timer.kind.symbolName)
                        }
                    }
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
                .frame(height: 26)
        }
        .tint(timer.kind.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((timer.kind == .betweenSides ? "Rest between sides" : "Rest") + (timer.isPaused ? ", paused" : ""))
        .accessibilityValue(DurationFormat.text(forSeconds: Int(timer.remaining(at: .now).rounded(.up))))
    }
}

extension RestKind {
    /// A rest between sides in its own color, so the bar says at a glance
    /// that the set is not over; the app's accent is the rest after a set.
    var tint: Color {
        switch self {
        case .afterSet: return .accentColor
        case .betweenSides: return .purple
        }
    }
}
