import SwiftUI

/// Pictures for the lists: small, decoded away from the main thread, kept
/// while there is memory. A list can hold many tiles, and a full photo in each
/// would make it stutter.
@MainActor
enum PhotoThumbnails {
    /// Enough for the widest tile on the largest screen, unzoomed.
    private static let longEdge = 720
    private static let cache = NSCache<NSString, UIImage>()

    /// The picture under its photo's `id`, which is new with every picture,
    /// big enough to stay sharp at `zoom`. `data` is only read when it is not
    /// cached yet.
    static func image(id: UUID, zoom: Double = 1, data: () -> Data) async -> UIImage? {
        let edge = min(Int(Double(longEdge) * max(zoom, 1)), PhotoFile.longEdge)
        let key = "\(id.uuidString)@\(edge)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = await decode(data(), longEdge: edge) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func decode(_ data: Data, longEdge: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            PhotoFile.scaled(data, longEdge: longEdge).map(UIImage.init(cgImage:))
        }.value
    }
}

/// An own exercise's photo in a list, in the shape of a catalog pictogram so
/// that the tiles stay in line; the part its framing says.
struct ExercisePhotoTile: View {
    let photo: ExercisePhoto
    @State private var image: UIImage?

    var body: some View {
        PhotoFrame(image: image, framing: photo.framing, aspectRatio: ExercisePictogram.aspectRatio)
            .task(id: "\(photo.id)\(photo.framingZoom)") {
                image = await PhotoThumbnails.image(id: photo.id, zoom: photo.framingZoom) { photo.data }
            }
    }
}

/// A machine's photo beside its name in a list: square, the part its framing
/// says.
struct MachinePhotoTile: View {
    let photo: MachinePhoto
    @State private var image: UIImage?

    var body: some View {
        PhotoFrame(image: image, framing: photo.framing, aspectRatio: 1)
            .task(id: "\(photo.id)\(photo.framingZoom)") {
                image = await PhotoThumbnails.image(id: photo.id, zoom: photo.framingZoom) { photo.data }
            }
    }
}

/// A photo in a rounded frame of `aspectRatio`, grey while it loads.
struct PhotoFrame: View {
    let image: UIImage?
    let framing: PhotoFraming
    let aspectRatio: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    FramedImage(image: image, framing: framing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The part of `image` that `framing` picks, filling whatever frame it is
/// given. The image is laid out larger than the frame and moved, so that the
/// visible part lands exactly in it.
struct FramedImage: View {
    let image: UIImage
    let framing: PhotoFraming

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rect = framing.visibleRect(
                imageAspect: image.size.width / max(image.size.height, 1),
                frameAspect: size.width / max(size.height, 1)
            )
            let width = size.width / rect.width
            let height = size.height / rect.height
            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: height)
                .offset(x: -rect.minX * width, y: -rect.minY * height)
        }
        .clipped()
    }
}
