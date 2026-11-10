#if os(macOS)
import AppKit
import Darwin
import Foundation
import OpenCoreGraphics

/// Measures the existing synchronous loop only when explicitly requested.
@main
private struct WindowLoopBaseline {
    /// Exercises a real GLFW loop; the external runner provides the hard timeout.
    @MainActor
    static func main() throws {
        let window = try WindowLoopProbe(frame: .init(x: 0, y: 0, width: 240, height: 180), title: "OCG baseline A")
        let second = try CGWindow(frame: .init(x: 260, y: 0, width: 240, height: 180), title: "OCG baseline B")
        guard let nativeSecond = NSApp.windows.first(where: { $0.title == "OCG baseline B" }) else {
            throw ProbeError.nativeWindowUnavailable
        }
        nativeSecond.orderFront(nil)

        var frames = 0
        var secondFrames = 0
        var injectedAt: UInt64?
        var latencies: [Double] = []
        var posted = 0
        var idleIterations = 0
        var animationFrames = 0
        var framesAtIdleStart = 0
        var framesAtIdleEnd = 0
        var idleCPUStart = 0.0
        var idleCPUEnd = 0.0
        var idleStart: UInt64 = 0
        var idleEnd: UInt64 = 0
        var closeRequested: UInt64 = 0
        let start = DispatchTime.now().uptimeNanoseconds
        var task: Task<Void, Never>?

        second.display = { secondFrames += 1 }
        window.display = { [weak window] in
            guard let window else { return }
            frames += 1
            let context = window.cgContext
            let phase = Double(frames % 2)
            context.setFillColor(CGColor(red: phase, green: 0, blue: 1 - phase, alpha: 1))
            context.fill(.init(x: 0, y: 0, width: 40, height: 40))
            animationFrames += 1
        }
        window.receivedEvent = { event in
            guard event.type == .keyDown, let sent = injectedAt else { return }
            latencies.append(Double(DispatchTime.now().uptimeNanoseconds - sent) / 1_000_000)
            injectedAt = nil
        }
        window.iteration = { [weak window] in
            guard let window else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = Double(now - start) / 1_000_000_000
            if task == nil {
                window.loopActive = true
                task = Task { @MainActor [weak window] in
                    guard let window else { return }
                    window.taskRan = true
                    window.taskRanDuringLoop = window.loopActive
                }
            }
            if elapsed >= 0.5 && idleStart == 0 {
                print("WINDOW_BASELINE idle_started")
                fflush(nil)
                idleStart = now
                idleCPUStart = Self.processCPUSeconds()
                framesAtIdleStart = frames
                window.viewsNeedDisplay = false
            }
            if idleStart != 0 && idleEnd == 0 {
                idleIterations += 1
            }
            if elapsed >= 2.5 && idleEnd == 0 {
                print("WINDOW_BASELINE idle_finished")
                fflush(nil)
                idleEnd = now
                idleCPUEnd = Self.processCPUSeconds()
                framesAtIdleEnd = frames
                window.viewsNeedDisplay = true
            }
            if elapsed >= 2.5 && elapsed < 4.5 && injectedAt == nil && posted < 20,
               let nativeWindow = NSApp.windows.first(where: { $0.title == "OCG baseline A" }),
               let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: nativeWindow.windowNumber, context: nil, characters: "a",
                charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
               ) {
                injectedAt = DispatchTime.now().uptimeNanoseconds
                posted += 1
                NSApp.postEvent(event, atStart: false)
            }
            if elapsed >= 4.5 {
                closeRequested = now
                NSApp.windows.first(where: { $0.title == "OCG baseline A" })?.performClose(nil)
            }
        }

        print("WINDOW_BASELINE entering_loop")
        fflush(nil)
        window.makeKeyAndOrderFront()
        print("WINDOW_BASELINE loop_returned")
        fflush(nil)
        let returned = DispatchTime.now().uptimeNanoseconds
        window.loopActive = false
        task?.cancel()
        let secondAutomaticFrames = secondFrames
        second.displayIfNeeded()

        let idleSeconds = Double(idleEnd - idleStart) / 1_000_000_000
        let cpuPercent = (idleCPUEnd - idleCPUStart) / idleSeconds * 100
        let closeMilliseconds = Double(returned - closeRequested) / 1_000_000
        print("WINDOW_BASELINE idle_seconds=\(idleSeconds) idle_cpu_seconds=\(idleCPUEnd - idleCPUStart) idle_cpu_percent_one_core=\(cpuPercent) idle_iterations=\(idleIterations)")
        print("WINDOW_BASELINE events_posted=\(posted) events_received=\(latencies.count) event_latency_ms=\(latencies)")
        print("WINDOW_BASELINE frames=\(frames) animation_frames=\(animationFrames) idle_draws=\(framesAtIdleEnd - framesAtIdleStart) second_automatic_frames=\(secondAutomaticFrames) second_after_manual_redraw=\(secondFrames) task_during_loop=\(window.taskRanDuringLoop) task_at_return=\(window.taskRan) close_ms=\(closeMilliseconds)")
        guard idleStart > 0, idleEnd > idleStart, closeRequested > 0,
              cpuPercent.isFinite, posted > 0, latencies.count == posted, animationFrames > 0 else {
            throw ProbeError.incompleteMeasurement
        }
        print("WINDOW_BASELINE COMPLETE")
        fflush(nil)
    }

    /// Returns process user plus system CPU time in seconds.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}

/// Indicates that the environment could not complete the measurement.
private enum ProbeError: Error {
    /// AppKit did not expose the expected native window.
    case nativeWindowUnavailable
    /// One or more measurements were not obtained.
    case incompleteMeasurement
}
#else
/// Reports that the AppKit-specific probe is unavailable on this platform.
@main
private enum WindowLoopBaselineUnavailable {
    /// Stops rather than reporting a fabricated measurement.
    static func main() {
        fatalError("The window baseline probe requires macOS and an AppKit graphical session.")
    }
}
#endif
