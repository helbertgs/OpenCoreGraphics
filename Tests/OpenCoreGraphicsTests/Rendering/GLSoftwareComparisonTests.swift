import Foundation
import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Compares OpenGL and software output when explicitly enabled on a machine with a display.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
@MainActor
struct GLSoftwareComparisonTests {
    /// Verifies the two rendering backends stay within their scene-specific mean channel tolerances.
    @Test
    func comparesSharedScenesAcrossBackends() throws {
        let window: CGWindow
        do {
            window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 64, height: 64), title: "Renderer comparison")
        } catch let error as CGWindowError {
            print("GL_RUNNER_GRAPHICS_UNAVAILABLE: \(error)")
            throw error
        }
        let glContext = window.cgContext
        let softwareContext = try #require(
            CGContext(
                data: nil,
                width: glContext.width,
                height: glContext.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .sRGB,
                bitmapInfo: 0
            )
        )
        let image = makeImage()

        for scene in ComparisonScene.allCases {
            try #require(
                glfwGetCurrentContext() == window.windowRef,
                "The comparison window must own the current GL context"
            )
            draw(scene, in: glContext, image: image)
            draw(scene, in: softwareContext, image: image)
            glContext.flush()
            softwareContext.flush()

            try #require(
                glfwGetCurrentContext() == window.windowRef,
                "The comparison window must remain the current GL context during readback"
            )
            let glPixels = try #require(glContext.renderTarget?.readPixels())
            glad_glFinish()
            let synchronizedPixels = try #require(glContext.renderTarget?.readPixels())
            #expect(glPixels == synchronizedPixels, "Readback changed after glFinish for \(scene.rawValue)")
            let softwarePixels = try GLComparisonPixels(pixels: softwareContext.data, storedAsSRGB: true).data
            try #require(glPixels.count == softwarePixels.count)
            let glBytes = [UInt8](glPixels)
            let softwareBytes = [UInt8](softwarePixels)
            #expect(stride(from: 0, to: glBytes.count, by: 4).contains {
                glBytes[$0] != 0 || glBytes[$0 + 1] != 0 || glBytes[$0 + 2] != 0
            }, "The GL scene \(scene.rawValue) must contain visible colored pixels")
            #expect(stride(from: 0, to: softwareBytes.count, by: 4).contains {
                softwareBytes[$0] != 0 || softwareBytes[$0 + 1] != 0 || softwareBytes[$0 + 2] != 0
            }, "The software scene \(scene.rawValue) must contain visible colored pixels")
            let normalizedGLPixels = try GLComparisonPixels(pixels: glPixels).data
            let difference = try #require(meanChannelDifference(normalizedGLPixels, softwarePixels))
            let tolerance = scene.hasCurvedEdges ? 4.0 / 255.0 : 2.0 / 255.0

            _ = try GLComparisonReport(
                scene: scene.rawValue,
                width: glContext.width,
                height: glContext.height,
                difference: difference,
                tolerance: tolerance,
                glPixels: glPixels,
                softwarePixels: softwarePixels
            )
            #expect(
                difference <= tolerance,
                "\(scene.rawValue) mean channel difference \(difference), allowed \(tolerance)"
            )
        }
        try compareMutableImage(in: glContext, and: softwareContext)
    }

    /// Compares both renderers across external pixel changes and queued image versions.
    /// - Parameters:
    ///   - glContext: The window-backed OpenGL destination.
    ///   - softwareContext: The independent bitmap destination.
    private func compareMutableImage(in glContext: CGContext, and softwareContext: CGContext) throws {
        let count = 4096
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        storage.initialize(repeating: 0, count: count)
        defer {
            storage.deinitialize(count: count)
            storage.deallocate()
        }
        storage[0] = 255
        storage[3] = 255
        let provider = CGDataProvider(data: Data(bytesNoCopy: storage, count: count, deallocator: .none))
        let image = CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: .sRGB, bitmapInfo: .byteOrder32Big, provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
        let full = CGRect(x: 0, y: 0, width: Double(glContext.width), height: Double(glContext.height))
        let left = CGRect(x: 0, y: 0, width: Double(glContext.width) / 2, height: Double(glContext.height))
        let right = CGRect(
            x: Double(glContext.width) / 2, y: 0,
            width: Double(glContext.width) / 2, height: Double(glContext.height)
        )
        glContext.interpolationQuality = .none
        softwareContext.interpolationQuality = .none
        glContext.draw(image, in: full)
        softwareContext.draw(image, in: full)
        let before = try compareMutableImagePixels(glContext, softwareContext, scene: "mutable_before")

        storage[0] = 0
        storage[1] = 255
        glContext.draw(image, in: full)
        softwareContext.draw(image, in: full)
        let after = try compareMutableImagePixels(glContext, softwareContext, scene: "mutable_after")
        #expect(before != after, "The GL readback must change after external pixels change")

        storage[0] = 255
        storage[1] = 0
        glContext.draw(image, in: left)
        softwareContext.draw(image, in: left)
        storage[0] = 0
        storage[1] = 255
        glContext.draw(image, in: right)
        softwareContext.draw(image, in: right)
        let queued = try compareMutableImagePixels(glContext, softwareContext, scene: "mutable_queued")
        let bytes = [UInt8](queued)
        let leftOffset = (glContext.height / 2 * glContext.width + glContext.width / 4) * 4
        let rightOffset = (glContext.height / 2 * glContext.width + 3 * glContext.width / 4) * 4
        #expect(bytes[leftOffset] > 240 && bytes[leftOffset + 1] < 15)
        #expect(bytes[rightOffset] < 15 && bytes[rightOffset + 1] > 240)
    }

    /// Flushes and compares a mutable-image scene, recording its visual evidence.
    /// - Parameters:
    ///   - glContext: The window-backed destination.
    ///   - softwareContext: The bitmap destination.
    ///   - scene: The identifier used by the comparison report.
    /// - Returns: The raw OpenGL framebuffer bytes.
    private func compareMutableImagePixels(
        _ glContext: CGContext,
        _ softwareContext: CGContext,
        scene: String
    ) throws -> Data {
        glContext.flush()
        softwareContext.flush()
        let glPixels = try #require(glContext.renderTarget?.readPixels())
        let softwarePixels = try GLComparisonPixels(pixels: softwareContext.data, storedAsSRGB: true).data
        let normalized = try GLComparisonPixels(pixels: glPixels).data
        let difference = try #require(meanChannelDifference(normalized, softwarePixels))
        let tolerance = 2.0 / 255.0
        _ = try GLComparisonReport(
            scene: scene, width: glContext.width, height: glContext.height,
            difference: difference, tolerance: tolerance, glPixels: glPixels, softwarePixels: softwarePixels
        )
        #expect(difference <= tolerance, "\(scene) mean channel difference \(difference), allowed \(tolerance)")
        return glPixels
    }

    /// Renders one scene using public context operations shared by both backends.
    /// - Parameters:
    ///   - scene: The shapes to draw.
    ///   - context: The destination context.
    ///   - image: The source bitmap used by the image scene.
    private func draw(_ scene: ComparisonScene, in context: CGContext, image: CGImage) {
        let scale = Double(min(context.width, context.height)) / 64
        let point: (Double, Double) -> OpenCoreGraphics.CGPoint = { x, y in
            CGPoint(x: x * scale, y: y * scale)
        }

        context.setBlendMode(.normal)
        context.setFillColor(.black)
        context.fill(CGRect(x: 0, y: 0, width: Double(context.width), height: Double(context.height)))

        switch scene {
        case .rectangle:
            context.setFillColor(CGColor(red: 0.9, green: 0.25, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 8 * scale, y: 8 * scale, width: 48 * scale, height: 48 * scale))
        case .ellipse:
            context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 1))
            context.fillEllipse(
                in: CGRect(x: 9 * scale, y: 15 * scale, width: 46 * scale, height: 34 * scale)
            )
        case .evenOddStar:
            var star = CGPath()
            star.move(to: point(32, 5))
            star.addLine(to: point(39, 25))
            star.addLine(to: point(60, 25))
            star.addLine(to: point(43, 38))
            star.addLine(to: point(50, 59))
            star.addLine(to: point(32, 46))
            star.addLine(to: point(14, 59))
            star.addLine(to: point(21, 38))
            star.addLine(to: point(4, 25))
            star.addLine(to: point(25, 25))
            star.closeSubpath()
            context.setFillColor(CGColor(red: 1, green: 0.7, blue: 0.1, alpha: 1))
            context.beginPath()
            context.addPath(star)
            context.fillPath(using: .evenOdd)
        case .roundJoinStroke:
            context.setStrokeColor(CGColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1))
            context.setLineWidth(10 * scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: point(12, 12))
            context.addLine(to: point(48, 12))
            context.addLine(to: point(48, 48))
            context.strokePath()
        case .image:
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 8 * scale, y: 8 * scale, width: 48 * scale, height: 48 * scale)
            )
        case .clipIntersection:
            context.saveGState()
            context.clip(to: CGRect(x: 12 * scale, y: 12 * scale, width: 40 * scale, height: 40 * scale))
            context.beginPath()
            context.addPath(
                CGPath(ellipseIn: CGRect(x: 5 * scale, y: 8 * scale, width: 54 * scale, height: 48 * scale))
            )
            context.clip()
            context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64 * scale, height: 64 * scale))
            context.restoreGState()
        }
    }

    /// Creates a small asymmetric image so vertical orientation is included in the comparison.
    /// - Returns: A two-by-two opaque RGBA image.
    private func makeImage() -> CGImage {
        CGImage(
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: CGDataProvider(data: Data([
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ])),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Computes the normalized mean absolute difference across all byte channels.
    /// - Parameters:
    ///   - first: The OpenGL RGBA pixels.
    ///   - second: The software RGBA pixels.
    /// - Returns: A value from zero to one, or nil when the buffers differ in size.
    private func meanChannelDifference(_ first: Data, _ second: Data) -> Double? {
        guard first.count == second.count, first.isEmpty == false else { return nil }
        let totalDifference = zip(first, second).reduce(0) { total, pair in
            total + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDifference) / Double(first.count * 255)
    }
}

/// The representative geometry and image cases included in the backend comparison.
private enum ComparisonScene: String, CaseIterable {
    /// A fast-path opaque rectangle.
    case rectangle

    /// An antialiased elliptical fill.
    case ellipse

    /// A self-intersecting star using the even-odd fill rule.
    case evenOddStar

    /// A stroke with round caps and joins.
    case roundJoinStroke

    /// A scaled, vertically asymmetric bitmap image.
    case image

    /// A solid rectangle intersected with both rectangular and elliptical clipping.
    case clipIntersection

    /// Whether scan conversion can differ at the scene's curved or stroked edges.
    var hasCurvedEdges: Bool {
        switch self {
        case .ellipse, .evenOddStar, .roundJoinStroke, .clipIntersection:
            true
        case .rectangle, .image:
            false
        }
    }
}
