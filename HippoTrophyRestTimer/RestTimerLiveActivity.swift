import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestTimerWidgets: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

/// The rest as the lock screen and the Dynamic Island show it. The system
/// counts down on its own: the app may be asleep when the rest ends, so
/// nothing here waits for an update. Past its end the activity is stale and
/// says so, until the app is opened again and ends it.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenRest(state: context.state, isOver: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isBetweenSides ? "Switch Sides" : "Rest", systemImage: context.state.symbolName)
                        .font(.headline)
                        .foregroundStyle(context.state.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state, isOver: context.isStale)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(context.state.tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.exerciseName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Bar(state: context.state, isOver: context.isStale)
                            .tint(context.state.tint)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(context.state.tint)
            } compactTrailing: {
                Countdown(state: context.state, isOver: context.isStale)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(context.state.tint)
                    .frame(maxWidth: 44)
            } minimal: {
                // Beside another app's activity this is all there is, so it
                // shows what is left; the color says which rest it is.
                Countdown(state: context.state, isOver: context.isStale, alignment: .center)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(context.state.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// A rest between sides looks the way it does in the app.
private extension RestActivityAttributes.ContentState {
    var symbolName: String {
        isBetweenSides ? "arrow.left.arrow.right" : "timer"
    }

    var tint: Color {
        isBetweenSides ? .purple : .accentColor
    }

    func title(isOver: Bool) -> String {
        if isBetweenSides {
            return isOver ? "Other Side" : pausedRemaining != nil ? "Switch Sides, Paused" : "Switch Sides"
        }
        return isOver ? "Rest Over" : pausedRemaining != nil ? "Rest Paused" : "Rest"
    }
}

private struct LockScreenRest: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(state.title(isOver: isOver), systemImage: state.symbolName)
                        .font(.headline)
                        .foregroundStyle(state.isBetweenSides ? state.tint : Color.primary)
                    Text(state.exerciseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Countdown(state: state, isOver: isOver)
                        .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    Text("of \(Duration.seconds(state.totalSeconds).formatted(.time(pattern: .minuteSecond)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Bar(state: state, isOver: isOver)
                .tint(state.tint)
        }
    }
}

/// Counts itself down: the system redraws a timer text without the app.
private struct Countdown: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool
    var alignment: TextAlignment = .trailing

    var body: some View {
        if isOver {
            Text("0:00")
        } else if let paused = state.pausedRemaining {
            Text(Duration.seconds(paused.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                .multilineTextAlignment(alignment)
        } else {
            Text(timerInterval: state.interval, countsDown: true)
                .multilineTextAlignment(alignment)
        }
    }
}

private struct Bar: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        if isOver {
            ProgressView(value: 0)
        } else if let paused = state.pausedRemaining {
            ProgressView(value: state.totalSeconds > 0 ? min(1, paused / Double(state.totalSeconds)) : 0)
        } else {
            ProgressView(timerInterval: state.interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
    }
}
