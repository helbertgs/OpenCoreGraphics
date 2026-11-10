import Foundation
import Testing
@testable import OpenCoreGraphics

@MainActor
struct CGContextCommandTests {
    /// Verifies that filling captures the fill rule and clears the current path.
    @Test
    func fillPathRecordsRuleAndClearsPath() throws {
        let (context, target) = makeRecordingContext()
        context.setFillColor(.black)
        context.beginPath()
        context.move(to: CGPoint(x: 1, y: 2))
        context.addLine(to: CGPoint(x: 5, y: 6))
        let path = try #require(context.path)

        context.fillPath(using: .evenOdd)
        context.flush()

        #expect(context.path == nil)
        #expect(target.commands == [.fillPath(path: path, rule: .evenOdd, color: .black, blendMode: .normal)])
    }

    /// Verifies public clip regions are tracked, restored, and reset in order.
    @Test
    func publicClipAPIsTrackAndRestoreRegions() {
        let (context, target) = makeRecordingContext()
        let rectangle = CGRect(x: 3.25, y: 4.5, width: 18.5, height: 20.25)
        context.clip(to: rectangle)
        #expect(context.boundingBoxOfClipPath == rectangle)
        #expect(target.clipRegions == [.rectangle(rectangle)])

        context.saveGState()
        context.beginPath()
        context.addPath(CGPath(ellipseIn: CGRect(x: 5, y: 6, width: 12, height: 14)))
        context.clip(using: .evenOdd)
        #expect(target.clipRegions.count == 2)

        context.restoreGState()
        #expect(target.clipRegions == [.rectangle(rectangle)])

        context.resetClip()
        #expect(target.clipRegions.isEmpty)
        #expect(context.boundingBoxOfClipPath == CGRect(x: 0, y: 0, width: 64, height: 64))

        let (rotatedContext, rotatedTarget) = makeRecordingContext()
        rotatedContext.rotate(by: .pi / 4)
        rotatedContext.clip(to: rectangle)
        let usesPathClip = rotatedTarget.clipRegions.first.map { region in
            if case .path = region { true } else { false }
        } ?? false
        #expect(usesPathClip)
    }

    /// Rebuilds clip coverage for resized and restored graphics states.
    @Test
    func resizingRebuildsCurrentAndSavedClipCoverage() throws {
        let (context, target) = makeRecordingContext()
        let first = CGRect(x: 2, y: 2, width: 10, height: 10)
        let second = CGRect(x: 6, y: 6, width: 10, height: 10)
        context.clip(to: first)
        context.saveGState()
        context.clip(to: second)
        context.resizeWindowContext(20, 18)
        let firstMask = try #require(CoverageMask(path: CGPath(rect: first), rule: .winding, width: 20, height: 18))
        let secondMask = try #require(CoverageMask(path: CGPath(rect: second), rule: .winding, width: 20, height: 18))
        let combined = try #require(firstMask.intersecting(secondMask))
        #expect(Mirror(reflecting: context).descendant("clipMask") as? CoverageMask == combined)
        #expect(context.boundingBoxOfClipPath == CGRect(x: 6, y: 6, width: 6, height: 6))

        context.restoreGState()

        #expect(Mirror(reflecting: context).descendant("clipMask") as? CoverageMask == firstMask)
        #expect(target.clipRegions == [.rectangle(first)])
        #expect(context.boundingBoxOfClipPath == first)
    }

    /// Reports invalid clip reconstruction and excludes pixels until coverage can be rebuilt.
    @Test
    func invalidResizeFailsClosedAndRecoversClipCoverage() throws {
        let (context, target) = makeRecordingContext()
        let clip = CGRect(x: 2, y: 2, width: 10, height: 10)
        context.clip(to: clip)
        context.saveGState()

        context.resizeWindowContext(0, 20)
        #expect(context.clipCoverageError == .rasterizationFailed)
        #expect(Mirror(reflecting: context).descendant("clipMask") as? CoverageMask == .empty)
        #expect(target.clipRegions == [.rectangle(clip)])

        context.resizeWindowContext(20, 20)
        let expected = try #require(CoverageMask(path: CGPath(rect: clip), rule: .winding, width: 20, height: 20))
        #expect(context.clipCoverageError == nil)
        #expect(Mirror(reflecting: context).descendant("clipMask") as? CoverageMask == expected)
        context.restoreGState()
        #expect(context.clipCoverageError == nil)
        #expect(Mirror(reflecting: context).descendant("clipMask") as? CoverageMask == expected)
    }

    /// Confirms a failed coverage rebuild cannot paint outside the previous clip on a bitmap.
    @Test
    func failedCoverageRebuildDoesNotPaintUnclippedPixels() throws {
        let context = try #require(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .sRGB,
            bitmapInfo: 0
        ))
        context.data = Data(repeating: 0, count: 8 * 8 * 4)
        context.clip(to: CGRect(x: 2, y: 2, width: 3, height: 3))
        context.resizeWindowContext(0, 8)
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.flush()
        #expect(context.clipCoverageError == .rasterizationFailed)
        #expect(context.data == Data(repeating: 0, count: 8 * 8 * 4))

        context.resizeWindowContext(8, 8)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.flush()
        let pixels = [UInt8](context.data)
        let inside = (3 * 8 + 3) * 4
        #expect(Array(pixels[inside..<(inside + 4)]) == [255, 255, 255, 255])
        #expect(Array(pixels.prefix(4)) == [0, 0, 0, 0])
    }

    /// Verifies that stroking captures the current line state and clears the path.
    @Test
    func strokePathRecordsStyleAndClearsPath() throws {
        let (context, target) = makeRecordingContext()
        context.setStrokeColor(.white)
        context.setLineWidth(3)
        context.beginPath()
        context.move(to: CGPoint(x: 1, y: 2))
        context.addLine(to: CGPoint(x: 5, y: 6))
        let path = try #require(context.path)
        let style = StrokeStyle(width: 3, cap: .butt, join: .miter, miterLimit: 10, dashLengths: [])

        context.strokePath()
        context.flush()

        #expect(context.path == nil)
        #expect(target.commands == [.strokePath(path: path, color: .white, style: style, blendMode: .normal)])
    }

    /// Verifies line setters are captured in stroke commands and restored with graphics state.
    @Test
    func lineStyleSettersCaptureAndRestore() throws {
        let (context, target) = makeRecordingContext()
        context.setStrokeColor(.black)
        context.setLineCap(.round)
        context.setLineJoin(.bevel)
        context.setMiterLimit(5)
        context.setLineDash(phase: 3, lengths: [8, 4])
        context.saveGState()

        context.setLineCap(.square)
        context.setLineJoin(.miter)
        context.setMiterLimit(1)
        context.setLineDash(phase: 2, lengths: [4, 6])
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 10, y: 0))
        let changedPath = try #require(context.path)
        context.strokePath()

        context.restoreGState()
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 10, y: 0))
        let restoredPath = try #require(context.path)
        context.strokePath()
        context.flush()

        let changedStyle = StrokeStyle(
            width: 1,
            cap: .square,
            join: .miter,
            miterLimit: 1,
            dashPhase: 2,
            dashLengths: [4, 6]
        )
        let restoredStyle = StrokeStyle(
            width: 1,
            cap: .round,
            join: .bevel,
            miterLimit: 5,
            dashPhase: 3,
            dashLengths: [8, 4]
        )
        #expect(target.commands == [
            .strokePath(path: changedPath, color: .black, style: changedStyle, blendMode: .normal),
            .strokePath(path: restoredPath, color: .black, style: restoredStyle, blendMode: .normal)
        ])
    }

    /// Verifies that combined drawing records fill before stroke.
    @Test
    func fillStrokeRecordsTwoCommandsInOrder() throws {
        let (context, target) = makeRecordingContext()
        context.setFillColor(.black)
        context.setStrokeColor(.white)
        context.beginPath()
        context.addRect(CGRect(x: 2, y: 3, width: 4, height: 5))
        let path = try #require(context.path)
        let style = StrokeStyle(width: 1, cap: .butt, join: .miter, miterLimit: 10, dashLengths: [])

        context.drawPath(using: .fillStroke)
        context.flush()

        #expect(context.path == nil)
        #expect(target.commands == [
            .fillPath(path: path, rule: .winding, color: .black, blendMode: .normal),
            .strokePath(path: path, color: .white, style: style, blendMode: .normal)
        ])
    }

    /// Verifies that rectangle, ellipse, clear, and image operations are queued.
    @Test
    func shapeAndImageOperationsRecordCommands() {
        let (context, target) = makeRecordingContext()
        let firstRect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let secondRect = CGRect(x: 5, y: 6, width: 7, height: 8)
        let color = CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.setFillColor(color)
        context.setStrokeColor(.white)

        context.fill(firstRect)
        context.fill([firstRect, secondRect])
        context.stroke(firstRect)
        context.fillEllipse(in: firstRect)
        context.strokeEllipse(in: secondRect)
        context.clear(secondRect)
        context.flush()

        #expect(target.commands[0] == .fillPath(path: CGPath(rect: firstRect), rule: .winding, color: color, blendMode: .normal))
        #expect(target.commands[1] == .fillPath(path: CGPath(rect: firstRect), rule: .winding, color: color, blendMode: .normal))
        #expect(target.commands[2] == .fillPath(path: CGPath(rect: secondRect), rule: .winding, color: color, blendMode: .normal))
        #expect(target.commands[3] == .strokePath(path: CGPath(rect: firstRect), color: .white, style: .init(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []), blendMode: .normal))
        #expect(target.commands[4] == .fillPath(path: CGPath(ellipseIn: firstRect), rule: .winding, color: color, blendMode: .normal))
        #expect(target.commands[5] == .strokePath(path: CGPath(ellipseIn: secondRect), color: .white, style: .init(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []), blendMode: .normal))
        #expect(target.commands[6] == .fillPath(path: CGPath(rect: secondRect), rule: .winding, color: .clear, blendMode: .clear))

        let provider = CGDataProvider(data: Data([255, 0, 0, 255]))
        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: .sRGB,
            bitmapInfo: .byteOrderDefault,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        context.draw(image, in: firstRect)
        context.flush()

        #expect(target.commands[7] == .drawImage(
            image: CGImageSnapshot(image: image),
            destination: [
                CGPoint(x: firstRect.minX, y: firstRect.minY),
                CGPoint(x: firstRect.maxX, y: firstRect.minY),
                CGPoint(x: firstRect.maxX, y: firstRect.maxY),
                CGPoint(x: firstRect.minX, y: firstRect.maxY)
            ],
            interpolationQuality: .default,
            byTiling: false,
            blendMode: .normal
        ))
    }

    /// Verifies image commands capture the affine destination and sampling options.
    @Test
    func drawImageCapturesTransformedQuadAndSamplingOptions() throws {
        let (context, target) = makeRecordingContext()
        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: CGDataProvider(data: Data([1, 2, 3, 4])),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let transform = CGAffineTransform.translate(8, 9) * .rotate(.pi / 4)
        context.ctm = transform
        context.interpolationQuality = .none

        context.draw(image, in: rect, byTiling: true)
        context.flush()

        let expectedCorners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { $0.applying(transform) }
        #expect(target.commands == [
            .drawImage(
                image: CGImageSnapshot(image: image),
                destination: expectedCorners,
                interpolationQuality: .none,
                byTiling: true,
                blendMode: .normal
            )
        ])
    }

    /// Verifies fill and stroke ellipse paths use the same current transformation.
    @Test
    func ellipseOperationsApplyCurrentTransformConsistently() {
        let (context, target) = makeRecordingContext()
        let rect = CGRect(x: 2, y: 3, width: 10, height: 8)
        let transform = CGAffineTransform.translate(7, 11) * .scale(2, 3)
        context.ctm = transform
        context.setFillColor(.black)
        context.setStrokeColor(.white)

        context.fillEllipse(in: rect)
        context.strokeEllipse(in: rect)
        context.flush()

        #expect(target.commands == [
            .fillPath(
                path: CGPath(ellipseIn: rect, transform: transform),
                rule: .winding,
                color: .black,
                blendMode: .normal
            ),
            .strokePath(
                path: CGPath(ellipseIn: rect, transform: transform),
                color: .white,
                style: StrokeStyle(width: 1, cap: .butt, join: .miter, miterLimit: 10, dashLengths: []),
                blendMode: .normal
            )
        ])
    }

    /// Verifies shadows are captured in draw commands and restored with the graphics state.
    @Test
    func capturesAndRestoresShadowState() {
        let (context, target) = makeRecordingContext()
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let shadow = CGShadow(offset: CGSize(width: 4, height: 5), blur: 2, color: .black)
        context.setFillColor(.white)
        context.saveGState()
        context.setShadow(offset: shadow.offset, blur: shadow.blur, color: shadow.color)
        context.fill(rect)
        context.restoreGState()
        context.fill(rect)
        context.flush()

        #expect(target.commands == [
            .fillPath(
                path: CGPath(rect: rect),
                rule: .winding,
                color: .white,
                blendMode: .normal,
                shadow: shadow
            ),
            .fillPath(path: CGPath(rect: rect), rule: .winding, color: .white, blendMode: .normal)
        ])
    }

    /// Verifies gradient commands capture transformed geometry, options, and blend mode.
    @Test
    func gradientOperationsRecordDeviceSpaceCommands() throws {
        let (context, target) = makeRecordingContext()
        let gradient = try #require(CGGradient(colors: [.black, .white], locations: [0, 1]))
        let linearOptions: CGGradientDrawingOptions = [.drawsBeforeStartLocation]
        let radialOptions: CGGradientDrawingOptions = [.drawsAfterEndLocation]
        context.ctm = .translate(10, 20)
        context.setBlendMode(.screen)

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 1, y: 2),
            end: CGPoint(x: 3, y: 4),
            options: linearOptions
        )
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: 1, y: 2),
            startRadius: 2,
            endCenter: CGPoint(x: 3, y: 4),
            endRadius: 4,
            options: radialOptions
        )
        context.flush()

        #expect(target.commands == [
            .linearGradient(
                gradient: gradient,
                start: CGPoint(x: 11, y: 22),
                end: CGPoint(x: 13, y: 24),
                options: linearOptions,
                blendMode: .screen
            ),
            .radialGradient(
                gradient: gradient,
                startCenter: CGPoint(x: 11, y: 22),
                startRadius: 2,
                endCenter: CGPoint(x: 13, y: 24),
                endRadius: 4,
                options: radialOptions,
                blendMode: .screen
            )
        ])
    }

    /// Verifies four points create two independent transformed line segments.
    @Test
    func strokeLineSegmentsRecordsOneSubpathPerPointPair() throws {
        let (context, target) = makeRecordingContext()
        let transform = CGAffineTransform.translate(10, 20)
        let points = [
            CGPoint(x: 1, y: 2),
            CGPoint(x: 3, y: 4),
            CGPoint(x: 5, y: 6),
            CGPoint(x: 7, y: 8)
        ]
        context.ctm = transform
        context.setStrokeColor(.white)

        context.strokeLineSegments(between: points)
        context.flush()

        var expectedPath = CGPath()
        expectedPath.move(to: points[0].applying(transform))
        expectedPath.addLine(to: points[1].applying(transform))
        expectedPath.move(to: points[2].applying(transform))
        expectedPath.addLine(to: points[3].applying(transform))
        let command = try #require(target.commands.first)
        #expect(target.commands.count == 1)
        #expect(command == .strokePath(
            path: expectedPath,
            color: .white,
            style: StrokeStyle(width: 1, cap: .butt, join: .miter, miterLimit: 10, dashLengths: []),
            blendMode: .normal
        ))
    }

    /// Verifies fill and stroke color convenience methods capture their color spaces.
    @Test
    func colorConvenienceMethodsCaptureColorsAndBlendMode() {
        let (context, target) = makeRecordingContext()
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let cmyk = CGColor(cyan: 0.1, magenta: 0.2, yellow: 0.3, black: 0.4, alpha: 0.5)
        let gray = CGColor(gray: 0.6, alpha: 0.7)
        let rgb = CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.5)

        context.setFillColor(cyan: 0.1, magenta: 0.2, yellow: 0.3, black: 0.4, alpha: 0.5)
        context.fill(rect)
        context.setFillColor(gray: 0.6, alpha: 0.7)
        context.fill(rect)
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.5)
        context.fill(rect)
        context.setFillColorSpace(.sRGB)
        context.setFillColor(.white)
        context.fill(rect)

        context.setStrokeColor(cyan: 0.1, magenta: 0.2, yellow: 0.3, black: 0.4, alpha: 0.5)
        context.setBlendMode(.multiply)
        context.stroke(rect)
        context.setStrokeColor(gray: 0.6, alpha: 0.7)
        context.stroke(rect)
        context.setStrokeColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.5)
        context.setStrokeColorSpace(.sRGB)
        context.setStrokeColor(.white)
        context.stroke(rect)
        context.setRenderingIntent(.absoluteColorimetric)
        context.flush()

        #expect(target.commands[0] == .fillPath(path: CGPath(rect: rect), rule: .winding, color: cmyk, blendMode: .normal))
        #expect(target.commands[1] == .fillPath(path: CGPath(rect: rect), rule: .winding, color: gray, blendMode: .normal))
        #expect(target.commands[2] == .fillPath(path: CGPath(rect: rect), rule: .winding, color: rgb, blendMode: .normal))
        #expect(target.commands[3] == .fillPath(path: CGPath(rect: rect), rule: .winding, color: .white, blendMode: .normal))
        #expect(target.commands[4] == .strokePath(path: CGPath(rect: rect), color: cmyk, style: .init(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []), blendMode: .multiply))
        #expect(target.commands[5] == .strokePath(path: CGPath(rect: rect), color: gray, style: .init(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []), blendMode: .multiply))
        #expect(target.commands[6] == .strokePath(path: CGPath(rect: rect), color: .white, style: .init(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []), blendMode: .multiply))
    }

    /// Verifies even-odd draw modes queue fill and stroke commands in order.
    @Test
    func evenOddDrawModesRecordCommands() throws {
        let (context, target) = makeRecordingContext()
        let rect = CGRect(x: 2, y: 3, width: 4, height: 5)
        context.setFillColor(.black)
        context.setStrokeColor(.white)
        context.beginPath()
        context.addRect(rect)
        let path = try #require(context.path)

        context.drawPath(using: .eoFill)
        context.beginPath()
        context.addRect(rect)
        context.drawPath(using: .eoFillStroke)
        context.flush()

        #expect(target.commands == [
            .fillPath(path: path, rule: .evenOdd, color: .black, blendMode: .normal),
            .fillPath(path: path, rule: .evenOdd, color: .black, blendMode: .normal),
            .strokePath(path: path, color: .white, style: .init(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []), blendMode: .normal)
        ])
    }

    /// Creates a bitmap context connected to an in-memory recording target.
    /// - Returns: The context and its target for inspecting submitted commands.
    private func makeRecordingContext() -> (CGContext, RecordingRenderTarget) {
        let context = CGContext(width: 64, height: 64)
        let target = RecordingRenderTarget(size: CGSize(width: 64, height: 64))
        context.renderTarget = target
        return (context, target)
    }
}
