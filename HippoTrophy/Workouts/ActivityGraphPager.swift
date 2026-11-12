import SwiftUI
import SwiftData

/// The activity graphs on the workout list, each on a card of its own, laid
/// side by side across the screen with one in view. Dragging the header moves
/// the cards along with the finger and lets go on the nearest one. The dots
/// below stay put and show where in the row the shown card is; the menu in
/// each card's header sets up which categories have a graph.
struct ActivityGraphPager: View {
    let sessions: [WorkoutSession]

    @Query private var definitions: [ExerciseDefinition]
    // Unset is Strength, then Cardio — see `ActivityGraphs`.
    @AppStorage(SettingsKey.activityGraphs) private var graphsStored = ""
    @State private var shownIndex = 0
    /// The row's width, for `PageSwipe`.
    @State private var width: CGFloat = 0
    /// The graphs of which at least a sliver can be seen, by `graphID`.
    @State private var inView: Set<String> = []
    /// The drag on the header while it lasts. It goes back to nil by itself
    /// when the drag ends or the list takes it over for scrolling.
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var drag: HeaderDrag?

    /// Which way a drag went once it got going: only a sideways one moves the
    /// row, so a drag that started as scrolling the list never pulls it along.
    private struct HeaderDrag {
        var isSideways: Bool
        var translation: CGFloat = 0
    }

    /// The card's corner, as round as the list's own sections.
    private static var cornerRadius: CGFloat { 26 }
    /// From the screen's edge to the card, and from the card's edge to the
    /// graph: the list's own margins, which this section sets to nothing so
    /// the cards can slide in from the edge.
    private static var margin: CGFloat { 16 }
    /// The visible stretch of the row, which the cards are measured against.
    private static var rowSpace: String { "activityGraphRow" }

    private var options: [CategoryFilter.Option] { CategoryFilter.options }

    var body: some View {
        let options = self.options
        let graphs = ActivityGraphs(stored: graphsStored, options: options)
        let categories = graphs.categories(options: options)
        // A graph removed elsewhere — its category deleted — can leave the
        // index past the end.
        let index = min(shownIndex, categories.count - 1)
        let swipe = PageSwipe(index: index, count: categories.count, pageWidth: width)
        let dragged = drag.map { $0.isSideways ? swipe.offset(for: $0.translation) : 0 } ?? 0

        VStack(spacing: 2) {
            cards(categories, shown: index, dragged: dragged, swipe: swipe, graphs: graphs, options: options)
            if categories.count > 1 {
                pageDots(count: categories.count, shown: index)
            }
        }
    }

    private func cards(
        _ categories: [CategoryFilter.Option],
        shown index: Int,
        dragged: CGFloat,
        swipe: PageSwipe,
        graphs: ActivityGraphs,
        options: [CategoryFilter.Option]
    ) -> some View {
        PageRow(position: CGFloat(index), dragged: dragged) {
            ForEach(Array(categories.enumerated()), id: \.element.graphID) { page, category in
                graph(category, at: page, shown: index, swipe: swipe, graphs: graphs, options: options)
                    .padding(.horizontal, Self.margin)
                    .padding(.vertical, 4)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: Self.cornerRadius, style: .continuous)
                    )
                    .padding(.horizontal, Self.margin)
                    .onGeometryChange(for: Bool.self) { proxy in
                        guard let row = proxy.bounds(of: .named(Self.rowSpace)) else { return false }
                        // Only touching the row's edge is out of view.
                        return row.intersection(CGRect(origin: .zero, size: proxy.size)).width > 0.5
                    } action: { isInView in
                        if isInView {
                            inView.insert(category.graphID)
                        } else {
                            inView.remove(category.graphID)
                        }
                    }
                    // Only the shown graph is there to touch and to read out.
                    .allowsHitTesting(page == index)
                    .accessibilityHidden(page != index)
            }
        }
        .coordinateSpace(.named(Self.rowSpace))
        // The width is only read for deciding where a drag lets go; the row
        // lays itself out from the width it is offered.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
    }

    private func graph(
        _ category: CategoryFilter.Option,
        at page: Int,
        shown index: Int,
        swipe: PageSwipe,
        graphs: ActivityGraphs,
        options: [CategoryFilter.Option]
    ) -> some View {
        ActivityGraphView(
            category: category,
            activity: ActivityGrid.activity(of: sessions, in: category, definitions: definitions),
            isInView: inView.contains(category.graphID),
            headerGesture: headerDrag(swipe),
            onTurn: { turn(to: index + $0, of: swipe.count) }
        ) {
            menu(graphs: graphs, index: page, options: options)
        }
    }

    private func headerDrag(_ swipe: PageSwipe) -> some Gesture {
        // Measured on the screen: the header moves along with the row, so in
        // its own space the finger would seem to cover half the way.
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($drag) { value, drag, _ in
                let moved = value.translation
                if drag == nil {
                    drag = HeaderDrag(isSideways: abs(moved.width) > abs(moved.height))
                }
                drag?.translation = moved.width
            }
            .onEnded { value in
                let moved = value.translation
                guard abs(moved.width) > abs(moved.height) else { return }
                let target = swipe.target(translation: moved.width, velocity: value.velocity.width)
                withAnimation(.snappy) { shownIndex = target }
            }
    }

    private func turn(to index: Int, of count: Int) {
        guard (0..<count).contains(index) else { return }
        withAnimation(.snappy) { shownIndex = index }
    }

    private func save(_ graphs: ActivityGraphs) {
        graphsStored = graphs.stored
    }

    /// Each dot takes a tap on more than itself, so a finger finds it.
    private func pageDots(count: Int, shown: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { page in
                Circle()
                    .fill(page == shown ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 7, height: 7)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { turn(to: page, of: count) }
            }
        }
        // The header's adjustable action turns the graphs for VoiceOver.
        .accessibilityHidden(true)
    }

    private func menu(graphs: ActivityGraphs, index: Int, options: [CategoryFilter.Option]) -> some View {
        let count = graphs.ids.count
        let unshown = graphs.unshown(options: options)

        return Menu {
            Section("This Graph Shows") {
                Picker("This Graph Shows", selection: Binding(
                    get: { CategoryFilter.id(of: graphs.categories(options: options)[index]) },
                    set: { id in
                        guard let option = options.first(where: { CategoryFilter.id(of: $0) == id }) else { return }
                        var changed = graphs
                        changed.replace(at: index, with: option)
                        save(changed)
                    }
                )) {
                    ForEach(graphs.choices(at: index, options: options), id: \.self) { option in
                        Label { Text(CategoryFilter.name(of: option)) } icon: { CategoryFilter.icon(of: option) }
                            .tag(CategoryFilter.id(of: option))
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                if !unshown.isEmpty {
                    Menu {
                        ForEach(unshown, id: \.self) { option in
                            Button {
                                var changed = graphs
                                if let added = changed.add(option, after: index) {
                                    save(changed)
                                    withAnimation(.snappy) { shownIndex = added }
                                }
                            } label: {
                                Label { Text(CategoryFilter.name(of: option)) } icon: { CategoryFilter.icon(of: option) }
                            }
                        }
                    } label: {
                        Label("Add Graph", systemImage: "plus")
                    }
                }
                if count > 1 {
                    Button {
                        var changed = graphs
                        shownIndex = changed.move(at: index, by: -1)
                        save(changed)
                    } label: {
                        Label("Move Left", systemImage: "arrow.left")
                    }
                    .disabled(index == 0)
                    Button {
                        var changed = graphs
                        shownIndex = changed.move(at: index, by: 1)
                        save(changed)
                    } label: {
                        Label("Move Right", systemImage: "arrow.right")
                    }
                    .disabled(index == count - 1)
                    Button(role: .destructive) {
                        var changed = graphs
                        changed.remove(at: index)
                        save(changed)
                        shownIndex = min(index, changed.ids.count - 1)
                    } label: {
                        Label("Remove Graph", systemImage: "minus.circle")
                    }
                }
            }

            Section {
                Button {
                    save(.standard)
                    shownIndex = 0
                } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                }
                .disabled(graphs.isStandard)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Activity Graphs")
    }
}

private extension CategoryFilter.Option {
    /// Keeps a graph's own state — the tapped day, how far the grid is
    /// scrolled — with its category when the row is reordered.
    var graphID: String { CategoryFilter.id(of: self) }
}

/// Pages side by side, each as wide as the row and touching the next, with `position` the page in
/// view and `dragged` how far the finger has moved the row off it. It takes
/// its width from what it is offered rather than from the pages, which are
/// many times wider together than the row.
private struct PageRow: Layout {
    var position: CGFloat
    var dragged: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(position, dragged) }
        set { (position, dragged) = (newValue.first, newValue.second) }
    }

    private func pageWidth(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return subviews.first?.sizeThatFits(.unspecified).width ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = pageWidth(proposal, subviews)
        let page = ProposedViewSize(width: width, height: proposal.height)
        let height = subviews.map { $0.sizeThatFits(page).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let page = ProposedViewSize(width: bounds.width, height: bounds.height)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + (CGFloat(index) - position) * bounds.width + dragged
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: page)
        }
    }
}
