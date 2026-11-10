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
