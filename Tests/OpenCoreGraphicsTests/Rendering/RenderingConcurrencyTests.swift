import Foundation
import Testing
@testable import OpenCoreGraphics

/// Exercises the value transfer and independent bitmap rendering boundaries.
struct RenderingConcurrencyTests {
    /// Confirms captured image bytes do not alias externally mutable no-copy storage.
    @Test
    func imageSnapshotCopiesExternalStorageBeforeTransfer() async {
        let byteCount = 4096
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        storage.initialize(repeating: 0, count: byteCount)
        storage[0] = 1
        storage[1] = 2
        storage[2] = 3
        storage[3] = 4
        defer {
            storage.deinitialize(count: byteCount)
            storage.deallocate()
        }

        let source = Data(bytesNoCopy: storage, count: byteCount, deallocator: .none)
        var expected = Data(repeating: 0, count: byteCount)
        expected.replaceSubrange(0..<4, with: [1, 2, 3, 4])
        let provider = CGDataProvider(data: source)
        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        let snapshot = CGImageSnapshot(image: image)
        let directSnapshot = CGImageSnapshot(
            identity: UUID(),
            data: source,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            alphaInfo: .premultipliedLast,
            colorSpace: .sRGB,
            bitmapInfo: .byteOrder32Big
        )
        let command = DrawCommand.drawImage(
            image: snapshot,
            destination: [.zero],
            interpolationQuality: .none,
            byTiling: false,
            blendMode: .normal
        )

        storage[0] = 99
        #expect(source[0] == 99)
        provider.data = Data([5, 6, 7, 8])
        let transferred = await Task.detached { (command, snapshot, directSnapshot) }.value

        #expect(transferred.0 == command)
        #expect(transferred.1.data == expected)
        #expect(transferred.2.data == expected)
    }

    /// Verifies value snapshots retain their contents when their sources change and cross a task boundary.
    @Test
    func commandAndGlyphSnapshotsRemainIndependent() async throws {
        var path = CGPath()
        path.move(to: .zero)
        let originalPath = path
        var coverage = Data([255])
        let bitmap = CGGlyphBitmap(width: 1, height: 1, xOffset: 0, yOffset: 0, coverage: coverage)
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))
        let command = DrawCommand.fillPath(path: path, rule: .winding, color: .black, blendMode: .normal)
        let state = CGGraphicsState()
        path.addLine(to: CGPoint(x: 4, y: 4))
        coverage[0] = 0

        let transferred = await Task.detached { (command, atlas, state) }.value

        #expect(transferred.0 == .fillPath(path: originalPath, rule: .winding, color: .black, blendMode: .normal))
        #expect(transferred.1.coverage.contains(255))
        #expect(transferred.2.fillColor == .black)
        #expect(path != originalPath)
        #expect(coverage == Data([0]))
    }

    /// Renders independent bitmaps in detached tasks without transferring mutable contexts.
    @Test
    func independentBitmapsRenderWithoutMainActorIsolation() async throws {
        async let red = Task.detached { try renderBitmap(red: 1, green: 0) }.value
        async let green = Task.detached { try renderBitmap(red: 0, green: 1) }.value

        let (redPixels, greenPixels) = try await (red, green)
        #expect(redPixels == Data([255, 0, 0, 255]))
        #expect(greenPixels == Data([0, 255, 0, 255]))
    }

    /// Starts independent bitmap tasks from the main actor and renders on the concurrent executor.
    @MainActor
    @Test
    private func bitmapTasksLeaveMainActorAndKeepPixelsIndependent() async throws {
        let pixels = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            group.addTask { (0, try await renderConcurrentBitmap(red: 1, green: 0)) }
            group.addTask { (1, try await renderConcurrentBitmap(red: 0, green: 1)) }

            var results: [Int: Data] = [:]
            for try await (index, data) in group {
                results[index] = data
            }
            return results
        }

        #expect(pixels[0] == Data([255, 0, 0, 255]))
        #expect(pixels[1] == Data([0, 255, 0, 255]))
    }

    /// Renders a new bitmap on the concurrent executor without transferring its mutable context.
    /// - Parameters:
    ///   - red: The red fill component.
    ///   - green: The green fill component.
    /// - Returns: The rendered RGBA pixel.
    @concurrent
    private func renderConcurrentBitmap(red: Double, green: Double) async throws -> Data {
        try renderBitmap(red: red, green: green)
    }

    /// Creates and synchronously renders a bitmap entirely within its caller's isolation domain.
    /// - Parameters:
    ///   - red: The red fill component.
    ///   - green: The green fill component.
    /// - Returns: The rendered RGBA pixel.
    private nonisolated func renderBitmap(red: Double, green: Double) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .genericRGBLinear,
                bitmapInfo: 0
            )
        )
        context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.flush()
        return context.data
    }
}
