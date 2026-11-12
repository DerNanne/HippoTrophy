import SwiftUI
import UIKit

/// The templates on the start screen: one card each, side by side in a row
/// that scrolls sideways, with a card to make a new one at its end. A tap
/// on a card shows the template, to start a workout from; its menu edits,
/// adjusts it for today, renames, duplicates or archives it. A day variant
/// is tinted and says which day it is for. Holding a card picks it up, and
/// dragging it sideways moves it along the row, the others making room as
/// it passes them.
struct TemplateShelfView: View {
    /// On the shelf, in order.
    let templates: [WorkoutSession]
    let actions: Actions

    struct Actions {
        /// A tap on the card: show the template, with Start Workout.
        var start: (WorkoutSession) -> Void
        var edit: (WorkoutSession) -> Void
        /// A variant of the template for today, first on the shelf.
        var adjustForToday: (WorkoutSession) -> Void
        var rename: (WorkoutSession) -> Void
        var duplicate: (WorkoutSession) -> Void
        var archive: (WorkoutSession) -> Void
        /// While a card is dragged: the first template now stands where the
        /// second did.
        var move: (WorkoutSession, WorkoutSession) -> Void
        /// Once the drag lets go.
        var finishMoving: () -> Void
        var create: () -> Void
    }

    /// The card picked up, and how far it is off its place in the row.
    /// Its own gesture rather than the system's drag and drop: inside the
    /// list that one does not reliably lift a card, and it would carry the
    /// template out to other apps, which nothing here can use — see
    /// `HoldAndDrag`.
    @State private var dragged: WorkoutSession?
    @State private var dragOffset: CGFloat = 0
    /// How far the row has already moved the dragged card along, so it
    /// stays under the finger when its place changes.
    @State private var dragShift: CGFloat = 0

    private static var cardSize: CGSize { CGSize(width: 168, height: 128) }
    private static var spacing: CGFloat { 10 }
    private static var cornerRadius: CGFloat { 20 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                ForEach(templates) { template in
                    card(template)
                }
                newTemplateCard
            }
            .scrollTargetLayout()
        }
        // The finger moves the card, not the row.
        .scrollDisabled(dragged != nil)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.vertical, 4)
    }

    private func card(_ template: WorkoutSession) -> some View {
        // No Button: a button keeps the touch for itself, and holding the
        // card to pick it up would never reach `reorder`.
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                // Clear of the menu button in the corner.
                .padding(.trailing, 32)
            Text(template.exercises.isEmpty ? "No exercises yet" : TemplateShelf.exerciseLine(of: template))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(template.plannedFor == nil ? 3 : 2)
            Spacer(minLength: 0)
            if let day = template.plannedFor {
                DayVariantBadge(day: day)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            shape.fill(Color(.secondarySystemGroupedBackground))
            // A variant is temporary: tinted, so it does not pass for a
            // template kept for good.
            if template.plannedFor != nil {
                shape
                    .fill(.tint.opacity(0.12))
                    .strokeBorder(.tint.opacity(0.5), lineWidth: 1.5)
            }
        }
        .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .onTapGesture { actions.start(template) }
        .gesture(reorder(template))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the template, to start a workout from it")
        .accessibilityAction { actions.start(template) }
        .overlay(alignment: .topTrailing) {
            menu(for: template)
        }
        .scaleEffect(dragged === template ? 1.05 : 1)
        .shadow(color: .black.opacity(dragged === template ? 0.18 : 0), radius: 10, y: 4)
        .offset(x: dragged === template ? dragOffset : 0)
        .zIndex(dragged === template ? 1 : 0)
        .sensoryFeedback(.selection, trigger: dragged === template)
    }

    /// Hold, then drag sideways. Each time the card is half a place off
    /// its own, it takes the neighbour's place — see `TemplateShelf.step`.
    private func reorder(_ template: WorkoutSession) -> HoldAndDrag {
        HoldAndDrag {
            withAnimation(.snappy) { dragged = template }
            dragShift = 0
        } moved: { translation in
            let stride = Self.cardSize.width + Self.spacing
            if let index = templates.firstIndex(where: { $0 === template }) {
                let step = TemplateShelf.step(offset: translation - dragShift, stride: stride, index: index, count: templates.count)
                if step != 0 {
                    withAnimation(.snappy) {
                        actions.move(template, templates[index + step])
                    }
                    dragShift += CGFloat(step) * stride
                }
            }
            dragOffset = translation - dragShift
        } ended: {
            withAnimation(.snappy) {
                dragged = nil
                dragOffset = 0
            }
            dragShift = 0
            actions.finishMoving()
        }
    }

    private func menu(for template: WorkoutSession) -> some View {
        Menu {
            Button {
                actions.edit(template)
            } label: {
                Label("Edit Template", systemImage: "pencil")
            }
            Button {
                actions.adjustForToday(template)
            } label: {
                Label("Adjust for Today", systemImage: "calendar.badge.plus")
            }
            Button {
                actions.rename(template)
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }
            Button {
                actions.duplicate(template)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                actions.archive(template)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 22)
                .background(Color(.tertiarySystemFill), in: .capsule)
                .padding(10)
                .contentShape(.rect)
        }
        .accessibilityLabel("Template Actions")
    }

    private var newTemplateCard: some View {
        Button(action: actions.create) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                Text("New Template")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.tint)
            .frame(width: Self.cardSize.width * 0.7, height: Self.cardSize.height)
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(.tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Hold a card, then drag it: UIKit's long press, which leaves a swipe to
/// the row until it fires and then reports every move of the finger. A
/// SwiftUI drag on the card, even one that waits for a long press, keeps
/// the row from scrolling at all.
struct HoldAndDrag: UIGestureRecognizerRepresentable {
    var began: () -> Void
    /// How far the finger has moved sideways since the card was picked up.
    var moved: (CGFloat) -> Void
    var ended: () -> Void

    final class Coordinator {
        var startX: CGFloat = 0
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.4
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        // On the screen: the card moves with the finger, and in its own
        // space the finger would hardly seem to move at all.
        let x = recognizer.location(in: nil).x
        switch recognizer.state {
        case .began:
            context.coordinator.startX = x
            began()
        case .changed:
            moved(x - context.coordinator.startX)
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }
}
