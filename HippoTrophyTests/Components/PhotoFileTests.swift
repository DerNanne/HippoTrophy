import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HippoTrophy

struct PhotoFileTests {
    private func image(width: Int, height: Int, alpha: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
        ))
        if !alpha {
            context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(context.makeImage())
    }

    private func encoded(_ image: CGImage, as type: UTType = .jpeg, properties: [CFString: Any] = [:]) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        let properties = try properties(of: data)
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    private func type(of data: Data) throws -> String? {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceGetType(source) as String?
    }

    @Test func aBigPictureComesDownToTheLongEdge() throws {
        let prepared = try #require(PhotoFile.prepared(from: encoded(image(width: 4000, height: 3000))))
        let size = try size(of: prepared)
        #expect(size.width == PhotoFile.longEdge)
        #expect(size.height == 1200)
    }

    @Test func aSmallPictureIsNotBlownUp() throws {
        let prepared = try #require(PhotoFile.prepared(from: encoded(image(width: 300, height: 200))))
        let size = try size(of: prepared)
        #expect(size.width == 300)
        #expect(size.height == 200)
    }

    /// A photo taken in a gym says where. It must not leave with a backup.
    @Test func whereAPhotoWasTakenIsLeftOut() throws {
        let original = try encoded(image(width: 400, height: 300), properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.48, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.0, kCGImagePropertyGPSLongitudeRef: "E"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Some Lens"]
        ])
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try #require(PhotoFile.prepared(from: original))
        #expect(try properties(of: prepared)[kCGImagePropertyGPSDictionary] == nil)
        let exif = try properties(of: prepared)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] == nil)
    }

    /// A phone stores a portrait photo lying down and says so in the metadata.
    /// With that gone, the pixels have to stand up themselves.
    @Test func aPhotoStoredLyingDownStandsUp() throws {
        let original = try encoded(image(width: 400, height: 300), properties: [kCGImagePropertyOrientation: 6])
        let prepared = try #require(PhotoFile.prepared(from: original))
        let size = try size(of: prepared)
        #expect(size.width == 300)
        #expect(size.height == 400)
    }

    @Test func anyPictureBecomesAJPEG() throws {
        let png = try encoded(image(width: 100, height: 100, alpha: true), as: .png)
        let prepared = try #require(PhotoFile.prepared(from: png))
        #expect(try type(of: prepared) == UTType.jpeg.identifier)
    }

    /// A cut-out's transparent parts turn white, not the black a JPEG would
    /// give them by itself.
    @Test func aCutOutSitsOnWhite() throws {
        let png = try encoded(image(width: 16, height: 16, alpha: true), as: .png)
        let prepared = try #require(PhotoFile.prepared(from: png))
        let decoded = try #require(PhotoFile.scaled(prepared, longEdge: 16))
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let red = try #require(context.data?.load(as: UInt8.self))
        #expect(red > 240)
    }

    @Test(arguments: [Data(), Data("no picture".utf8)])
    func whatIsNoPictureIsSaid(data: Data) {
        #expect(PhotoFile.prepared(from: data) == nil)
        #expect(PhotoFile.arriving(data) == nil)
    }

    @Test func aPreparedPictureArrivesByteForByte() throws {
        let prepared = try #require(PhotoFile.prepared(from: encoded(image(width: 800, height: 600))))
        #expect(PhotoFile.arriving(prepared) == prepared)
    }

    @Test func aPictureAddedByHandIsPreparedOnTheWayIn() throws {
        let tooBig = try encoded(image(width: 3200, height: 1600))
        let arrived = try #require(PhotoFile.arriving(tooBig))
        #expect(try size(of: arrived).width == PhotoFile.longEdge)

        let png = try encoded(image(width: 100, height: 100), as: .png)
        #expect(try type(of: #require(PhotoFile.arriving(png))) == UTType.jpeg.identifier)
    }
}
