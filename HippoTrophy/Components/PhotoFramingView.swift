import SwiftUI

/// Picks the part of a photo its tile shows: drag to move, pinch to zoom, in a
/// frame of the tile's shape. The rest of the photo shows dimmed around it,
/// so it is clear what there is to move to. Done hands the framing over;
/// Cancel leaves it as it was.
struct PhotoFramingView: View {
    let image: UIImage
    let aspectRatio: CGFloat
    let onDone: (PhotoFraming) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Where the current gesture started from.
    @State private var settled: PhotoFraming
    @State private var drag: CGSize = .zero
    @State private var magnification: CGFloat = 1
    /// What of a gesture still under way is already in `settled`, because
    /// the other one ended first.
    @State private var dragSettled: CGSize = .zero
    @State private var magnificationSettled: CGFloat = 1

    init(image: UIImage, aspectRatio: CGFloat, framing: PhotoFraming, onDone: @escaping (PhotoFraming) -> Void) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.onDone = onDone
        _settled = State(initialValue: framing)
    }

    private var imageAspect: Double { image.size.width / max(image.size.height, 1) }

    /// What the frame shows right now, the gesture under way included.
    private func live(in frame: CGSize) -> PhotoFraming {
        let dx = drag.width - dragSettled.width
        let dy = drag.height - dragSettled.height
        return settled
            .zoomed(by: magnification / magnificationSettled, imageAspect: imageAspect, frameAspect: aspectRatio)
            .panned(
                dx: dx / max(frame.width, 1), dy: dy / max(frame.height, 1),
                imageAspect: imageAspect, frameAspect: aspectRatio
            )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let frame = frameSize(in: geometry.size)
                let framing = live(in: frame)
                ZStack {
                    Color.black
                    surroundings(framing: framing, frame: frame)
                    FramedImage(image: image, framing: framing)
                        .frame(width: frame.width, height: frame.height)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                // The dimmed photo stays between the bars, whatever its shape.
                .clipped()
                .overlay(alignment: .bottom) {
                    Text("Drag to move, pinch to zoom.")
                        .font(.footnote)
                        // Over the dimmed photo, grey would hardly show.
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { _ in
                            settled = live(in: frame)
                            drag = .zero
                            dragSettled = .zero
                            magnificationSettled = magnification
                        }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { magnification = $0.magnification }
                            .onEnded { _ in
                                settled = live(in: frame)
                                magnification = 1
                                magnificationSettled = 1
                                dragSettled = drag
                            })
                )
            }
            .background(Color.black)
            .navigationTitle("Adjust Framing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(settled)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") { settled = .centered }
                        .disabled(settled.isCentered)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
        }
        // Dark here only: `preferredColorScheme` would darken the form this
        // sheet was presented from, and leave it dark after.
        .environment(\.colorScheme, .dark)
    }

    /// The tile's shape, as large as fits with a margin.
    private func frameSize(in space: CGSize) -> CGSize {
        let width = min(space.width - 32, (space.height - 32) * aspectRatio)
        return CGSize(width: max(width, 1), height: max(width / aspectRatio, 1))
    }

    /// The whole photo at the frame's scale, dimmed, placed so that its
    /// visible part lies under the frame.
    private func surroundings(framing: PhotoFraming, frame: CGSize) -> some View {
        let rect = framing.visibleRect(imageAspect: imageAspect, frameAspect: aspectRatio)
        let width = frame.width / rect.width
        let height = frame.height / rect.height
        // From the centre of the frame to the centre of the photo.
        let dx = (0.5 - rect.midX) * width
        let dy = (0.5 - rect.midY) * height
        return Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
            .offset(x: dx, y: dy)
            .opacity(0.35)
            .allowsHitTesting(false)
    }
}
