import Foundation
import Testing
@testable import OpenCoreGraphics

struct DrawCommandTests {
    /// Verifies construction and value equality for every drawing command.
    @Test
    func commandsCaptureTheirRenderingState() {
        var path = CGPath()
        path.move(to: CGPoint(x: 2, y: 3))
        let color = CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let style = StrokeStyle(width: 2, cap: .round, join: .bevel, miterLimit: 4, dashPhase: 1, dashLengths: [3, 2])
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
        let imageSnapshot = CGImageSnapshot(image: image)
        let destination = [
            CGPoint(x: 4, y: 5),
            CGPoint(x: 10, y: 5),
            CGPoint(x: 10, y: 12),
            CGPoint(x: 4, y: 12)
        ]
        let commands: [DrawCommand] = [
            .fillPath(path: path, rule: .evenOdd, color: color, blendMode: .multiply),
            .strokePath(path: path, color: color, style: style, blendMode: .screen),
            .drawImage(
                image: imageSnapshot,
                destination: destination,
                interpolationQuality: .none,
                byTiling: true,
                blendMode: .normal
            ),
            .clip(path: path, rule: .winding),
            .glyphs(
                glyphs: [1, 2],
                positions: [CGPoint(x: 4, y: 5), CGPoint(x: 6, y: 7)],
                fontName: "Test",
                fontSize: 12,
                glyphBitmaps: [nil, nil],
                characterSpacing: 0,
                textMatrix: .identity,
                textPosition: .zero,
                ctm: .identity,
                color: color,
                blendMode: .normal
            )
        ]

        #expect(commands.count == 5)
        #expect(style.dashPhase == 1)
        #expect(style.dashLengths == [3, 2])
        #expect(commands[0] == .fillPath(path: path, rule: .evenOdd, color: color, blendMode: .multiply))
        #expect(commands[1] == .strokePath(path: path, color: color, style: style, blendMode: .screen))
        #expect(commands[2] == .drawImage(
            image: imageSnapshot,
            destination: destination,
            interpolationQuality: .none,
            byTiling: true,
            blendMode: .normal
        ))
        #expect(commands[3] == .clip(path: path, rule: .winding))
        #expect(commands[4] == .glyphs(
            glyphs: [1, 2],
            positions: [CGPoint(x: 4, y: 5), CGPoint(x: 6, y: 7)],
            fontName: "Test",
            fontSize: 12,
            glyphBitmaps: [nil, nil],
            characterSpacing: 0,
            textMatrix: .identity,
            textPosition: .zero,
            ctm: .identity,
            color: color,
            blendMode: .normal
        ))
    }
}
