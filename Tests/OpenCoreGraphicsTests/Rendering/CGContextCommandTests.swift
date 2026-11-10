import Foundation
import Testing
@testable import OpenCoreGraphics

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
        let style = StrokeStyle(width: 3, cap: .butt, join: .miter, miterLimit: 10, dash: [])

        context.strokePath()
        context.flush()

        #expect(context.path == nil)
        #expect(target.commands == [.strokePath(path: path, color: .white, style: style, blendMode: .normal)])
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
        let style = StrokeStyle(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: [])

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
            data: Data([255, 0, 0, 255]),
            width: 1,
            height: 1,
            destination: firstRect,
            blendMode: .normal
        ))
    }

    /// Creates a bitmap context connected to an in-memory recording target.
    /// - Returns: The context and its target for inspecting submitted commands.
    private func makeRecordingContext() -> (CGContext, RecordingRenderTarget) {
        let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .genericRGBLinear,
            bitmapInfo: 0
        )
        let target = RecordingRenderTarget(size: CGSize(width: 64, height: 64))
        context.renderTarget = target
        return (context, target)
    }
}
