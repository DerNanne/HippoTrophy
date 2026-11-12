import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a picture becomes before it is stored: at most `longEdge` pixels on
/// its long edge, as a JPEG, without the metadata it came with. One size for
/// the app and the backup, so a backup and its import lose nothing.
///
/// Metadata goes on purpose: a photo taken in a gym says where, and a backup
/// can be shared. A JPEG because a package should open on any computer.
///
/// Changing `longEdge` needs no migration; it holds for pictures from then on.
nonisolated enum PhotoFile {
    /// A portrait photo at this size is about as wide as an iPhone's screen.
    static let longEdge = 1600
    static let quality = 0.75

    /// A picture the user just picked, in any format ImageIO reads. Nil when
    /// the data is no picture.
    static func prepared(from data: Data) -> Data? {
        guard let image = scaled(data, longEdge: longEdge) else { return nil }
        return jpeg(image)
    }

    /// A picture out of a backup. One the app prepared stays byte for byte;
    /// anything else — a package put together by hand — is prepared here.
    static func arriving(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? .max
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? .max
        if CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, max(width, height) <= longEdge {
            return data
        }
        return prepared(from: data)
    }

    /// The picture at most `longEdge` pixels long, upright, never enlarged.
    static func scaled(_ data: Data, longEdge: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            // A JPEG has no transparency; a cut-out sits on white, not black.
            kCGImageDestinationBackgroundColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
