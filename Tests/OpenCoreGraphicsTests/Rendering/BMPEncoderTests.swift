import Foundation
import Testing
@testable import OpenCoreGraphics

/// Verifies BMP encoding, decoder compatibility, and reference-image comparisons.
struct BMPEncoderTests {
    /// Verifies a 4×4 surface round-trips through BMP and the stb_image decoder.
    @Test
    func exportsFourByFourSurfaceWithStraightAlphaAndTopDownRows() throws {
        let surface = try #require(
            PixelSurface(
                data: nil,
                width: 4,
                height: 4,
                bytesPerRow: 16,
                colorSpace: .sRGB,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrderDefault
            )
        )
        var expectedPixels: [UInt8] = []
        let alphaValues: [UInt8] = [0, 64, 128, 255]

        for index in 0..<16 {
            let alpha = alphaValues[index % alphaValues.count]
            let red = UInt8((index * 17) % 256)
            let green = UInt8((index * 31) % 256)
            let blue = UInt8((index * 47) % 256)
            let premultipliedRed = premultiply(red, alpha: alpha)
            let premultipliedGreen = premultiply(green, alpha: alpha)
            let premultipliedBlue = premultiply(blue, alpha: alpha)
            let pixel = PixelSurface.Pixel(
                red: premultipliedRed,
                green: premultipliedGreen,
                blue: premultipliedBlue,
                alpha: alpha
            )
            #expect(surface.setPixel(pixel, x: index % 4, y: index / 4))

            if alpha == 0 {
                expectedPixels.append(contentsOf: [0, 0, 0, 0])
            } else {
                expectedPixels.append(contentsOf: [
                    unpremultiply(premultipliedRed, alpha: alpha),
                    unpremultiply(premultipliedGreen, alpha: alpha),
                    unpremultiply(premultipliedBlue, alpha: alpha),
                    alpha
                ])
            }
        }

        let encodedBMP = try BMPEncoder.encode(surface: surface)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "OpenCoreGraphics-\(UUID().uuidString).bmp")
        defer {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        try encodedBMP.write(to: fileURL)

        let decodedImage = try #require(CGImage(url: fileURL.path))
        #expect(decodedImage.width == 4)
        #expect(decodedImage.height == 4)
        let decodedPixels = try #require(decodedImage.dataProvider?.data)
        #expect(Array(decodedPixels) == expectedPixels)
    }

    /// Verifies software rendering remains within a small mean channel difference of each golden BMP.
    @Test(arguments: ReferenceScene.allCases)
    private func matchesReferenceBitmap(_ scene: ReferenceScene) throws {
        let context = try render(scene)
        let difference = try meanChannelDifference(context: context, reference: scene)

        #expect(difference <= 0.5)
    }

    /// Renders a deterministic scene for one of the checked-in reference images.
    /// - Parameter scene: The shapes and colors represented by the reference image.
    /// - Returns: A flushed 64×64 bitmap context.
    private func render(_ scene: ReferenceScene) throws -> CGContext {
        let context = try #require(
            CGContext(
                data: nil,
                width: 64,
                height: 64,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .genericRGBLinear,
                bitmapInfo: 0
            )
        )

        switch scene {
        case .rectangle:
            context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.25, alpha: 0.5))
            context.fill(CGRect(x: 8, y: 8, width: 48, height: 48))
        case .circle:
            context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
            context.beginPath()
            context.addPath(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 48, height: 48)))
            context.fillPath()
        case .star:
            context.setFillColor(CGColor(red: 1, green: 0.7, blue: 0, alpha: 1))
            context.beginPath()
            context.addPath(fivePointStar())
            context.fillPath(using: .evenOdd)
        }

        context.flush()
        return context
    }

    /// Compares an encoded software bitmap to a bundled BMP reference.
    /// - Parameters:
    ///   - context: The rendered bitmap context.
    ///   - scene: The reference image paired with the scene.
    /// - Returns: The mean absolute difference across all RGBA channels.
    private func meanChannelDifference(context: CGContext, reference scene: ReferenceScene) throws -> Double {
        let colorSpace = try #require(context.colorSpace)
        let renderedBMP = try BMPEncoder.encode(
            bitmapData: context.data,
            width: context.width,
            height: context.height,
            bytesPerRow: context.bytesPerRow,
            colorSpace: colorSpace,
            alphaInfo: context.alphaInfo,
            bitmapInfo: context.bitmapInfo
        )
        let referenceURL = try #require(
            Bundle.module.url(forResource: scene.rawValue, withExtension: "bmp", subdirectory: "Resources")
        )
        let referenceImage = try #require(CGImage(url: referenceURL.path))
        let renderedBytes = Array(renderedBMP)
        let referenceSnapshot = CGImageSnapshot(image: referenceImage)
        let pixelOffset = Int(littleEndianUInt32(in: renderedBytes, at: 10))
        let pixelCount = context.width * context.height
        var totalDifference = 0

        guard referenceImage.width == context.width,
              referenceImage.height == context.height,
              let referenceData = referenceSnapshot.data else {
            Issue.record("Reference bitmap dimensions or pixel data are invalid.")
            return .infinity
        }

        for y in 0..<context.height {
            for x in 0..<context.width {
                let renderedOffset = pixelOffset + (y * context.width + x) * 4
                let referenceOffset = y * referenceSnapshot.bytesPerRow + x * 4
                let renderedRGBA = [
                    renderedBytes[renderedOffset + 2],
                    renderedBytes[renderedOffset + 1],
                    renderedBytes[renderedOffset],
                    renderedBytes[renderedOffset + 3]
                ]
                let referenceRGBA = (0..<4).map { referenceData[referenceOffset + $0] }
                for channel in 0..<4 {
                    totalDifference += abs(Int(renderedRGBA[channel]) - Int(referenceRGBA[channel]))
                }
            }
        }
        return Double(totalDifference) / Double(pixelCount * 4)
    }

    /// Decodes one little-endian 32-bit integer from a byte buffer.
    /// - Parameters:
    ///   - bytes: The serialized data.
    ///   - offset: The first byte of the integer.
    /// - Returns: The integer value.
    private func littleEndianUInt32(in bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    /// Converts one straight-alpha 8-bit channel to premultiplied form.
    /// - Parameters:
    ///   - value: The straight color channel.
    ///   - alpha: The 8-bit pixel alpha.
    /// - Returns: The rounded premultiplied channel.
    private func premultiply(_ value: UInt8, alpha: UInt8) -> UInt8 {
        UInt8((Int(value) * Int(alpha) + 127) / 255)
    }

    /// Converts one premultiplied 8-bit channel to straight-alpha form.
    /// - Parameters:
    ///   - value: The premultiplied color channel.
    ///   - alpha: The 8-bit pixel alpha.
    /// - Returns: The rounded straight-alpha channel.
    private func unpremultiply(_ value: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        return UInt8(min(255, (Int(value) * 255 + Int(alpha) / 2) / Int(alpha)))
    }

    /// Creates a closed five-point star centered in a 64×64 image.
    /// - Returns: A self-intersecting path for even-odd filling.
    private func fivePointStar() -> CGPath {
        let center = CGPoint(x: 32, y: 32)
        let vertices: [OpenCoreGraphics.CGPoint] = (0..<5).map { index in
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 5
            return CGPoint(x: center.x + 28 * cos(angle), y: center.y + 28 * sin(angle))
        }
        let order = [0, 2, 4, 1, 3]
        var path = CGPath()
        path.move(to: vertices[order[0]])
        for index in order.dropFirst() {
            path.addLine(to: vertices[index])
        }
        path.closeSubpath()
        return path
    }
}

/// A rendered scene with a matching checked-in BMP reference.
private enum ReferenceScene: String, CaseIterable, Sendable {
    /// A semi-transparent rectangle on a transparent background.
    case rectangle = "software-rectangle-alpha"

    /// An antialiased circle on a transparent background.
    case circle = "software-circle"

    /// A five-point star filled with the even-odd rule.
    case star = "software-star-even-odd"
}
