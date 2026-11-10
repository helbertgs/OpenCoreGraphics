import Foundation
import Testing
@testable import OpenCoreGraphics

@MainActor
struct CGRenderTargetTests {
    /// Verifies that a recording target preserves submitted command order.
    @Test
    func recordingTargetPreservesSubmissionOrder() {
        let target = RecordingRenderTarget(size: CGSize(width: 20, height: 10))
        let path = CGPath()
        let commands: [DrawCommand] = [
            .fillPath(path: path, rule: .winding, color: .black, blendMode: .normal),
            .clip(path: path, rule: .evenOdd),
            .strokePath(
                path: path,
                color: .black,
                style: StrokeStyle(width: 1, cap: .butt, join: .miter, miterLimit: 10, dash: []),
                blendMode: .normal
            )
        ]

        for command in commands {
            target.submit(command)
        }

        #expect(target.size == CGSize(width: 20, height: 10))
        #expect(target.commands == commands)
        #expect(target.readPixels() == nil)
    }
}
