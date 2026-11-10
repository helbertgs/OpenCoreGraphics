#if os(macOS)
import AppKit
import Foundation
import OpenCoreGraphics

/// Observes iterations and keyboard events without changing the window implementation.
@MainActor
final class WindowLoopProbe: CGWindow {
    /// Runs once per loop iteration, including when drawing is disabled.
    var iteration: () -> Void = {}

    /// Observes keyboard events delivered by the GLFW callback.
    var receivedEvent: (OpenCoreGraphics.CGEvent) -> Void = { _ in }

    /// Indicates whether the synchronous call has not yet returned.
    var loopActive = false

    /// Records execution of the queued actor task.
    var taskRan = false

    /// Records whether the task ran before the synchronous call returned.
    var taskRanDuringLoop = false

    /// Performs the probe before the existing redraw decision.
    override func displayIfNeeded() {
        iteration()
        super.displayIfNeeded()
    }

    /// Observes events delivered to this window.
    override func sendEvent(_ event: OpenCoreGraphics.CGEvent) {
        receivedEvent(event)
    }
}
#endif
