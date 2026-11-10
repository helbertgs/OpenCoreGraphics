#if os(macOS)
import AppKit
import Darwin
import Foundation
import OpenCoreGraphics

/// Measures the public cooperative window API in a separate graphical process.
@main
private struct WindowCooperativeProbe {
    /// Performs the graphical experiment under an external process timeout.
    @MainActor
    static func main() throws {
        print("WINDOW_COOPERATIVE started")
        fflush(nil)
        let application = NSApplication.shared
        var outcome: Result<Void, any Error>?
        Task { @MainActor in
            do {
                guard application.isRunning else { throw ProbeError.hostNotRunning }
                print("WINDOW_COOPERATIVE host_running")
                fflush(nil)
                let a = try ProbeWindow(frame: .init(x: 0, y: 0, width: 240, height: 180), title: "OCG cooperative A")
                let b = try ProbeWindow(frame: .init(x: 260, y: 0, width: 240, height: 180), title: "OCG cooperative B")
                try await run(a: a, b: b)
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            application.stop(nil)
            if let event = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
            ) {
                application.postEvent(event, atStart: true)
            }
        }
        application.run()
        guard let outcome else { throw ProbeError.incomplete }
        try outcome.get()
    }

    /// Exercises two participants and collects observations.
    @MainActor
    private static func run(a: ProbeWindow, b: ProbeWindow) async throws {
        let cancelledBeforeStart = Task { @MainActor in try await a.makeKeyAndOrderFrontAsync() }
        cancelledBeforeStart.cancel()
        do {
            try await cancelledBeforeStart.value
            throw ProbeError.incomplete
        } catch is CancellationError {
        }
        print("WINDOW_COOPERATIVE precancelled")
        fflush(nil)
        var framesA = 0
        var framesB = 0
        var injectedAt: UInt64?
        var latencies: [Double] = []
        a.display = { [weak a] in
            guard let a else { return }
            framesA += 1
            let phase = Double(framesA % 2)
            a.cgContext.setFillColor(CGColor(red: phase, green: 0, blue: 1 - phase, alpha: 1))
            a.cgContext.fill(.init(x: 0, y: 0, width: 40, height: 40))
        }
        b.display = { framesB += 1 }
        a.receivedEvent = { event in
            guard event.type == .keyDown, let sent = injectedAt else { return }
            latencies.append(Double(DispatchTime.now().uptimeNanoseconds - sent) / 1_000_000)
            injectedAt = nil
        }
        var taskA = Task { @MainActor in try await a.makeKeyAndOrderFrontAsync() }
        let taskB = Task { @MainActor in try await b.makeKeyAndOrderFrontAsync() }
        defer { taskA.cancel(); taskB.cancel() }

        try await waitUntil { framesA >= 3 && framesB >= 3 }
        do {
            try await a.makeKeyAndOrderFrontAsync()
            throw ProbeError.incomplete
        } catch is CancellationError {
            throw ProbeError.incomplete
        } catch ProbeError.incomplete {
            throw ProbeError.incomplete
        } catch {
            print("WINDOW_COOPERATIVE duplicate_rejected")
        }
        print("WINDOW_COOPERATIVE animated")
        fflush(nil)
        var actorTaskRan = false
        let actorTask = Task { @MainActor in actorTaskRan = true }
        await actorTask.value
        guard actorTaskRan else { throw ProbeError.incomplete }

        a.viewsNeedDisplay = false
        b.viewsNeedDisplay = false
        try await Task.sleep(for: .milliseconds(50))
        let start = DispatchTime.now().uptimeNanoseconds
        let cpuStart = processCPUSeconds()
        let idleFramesA = framesA
        let idleFramesB = framesB
        try await Task.sleep(for: .seconds(2))
        print("WINDOW_COOPERATIVE idle_finished")
        fflush(nil)
        let end = DispatchTime.now().uptimeNanoseconds
        let cpuEnd = processCPUSeconds()
        let idleDrawsA = framesA - idleFramesA
        let idleDrawsB = framesB - idleFramesB
        print("WINDOW_COOPERATIVE idle_draws_a=\(idleDrawsA) idle_draws_b=\(idleDrawsB)")
        fflush(nil)
        guard idleDrawsA == 0, idleDrawsB == 0 else { throw ProbeError.incomplete }

        a.viewsNeedDisplay = true
        try await waitUntil { framesA > idleFramesA }
        a.viewsNeedDisplay = false
        print("WINDOW_COOPERATIVE redraw_finished")
        fflush(nil)
        guard let nativeA = NSApp.windows.first(where: { $0.title == "OCG cooperative A" }),
              let nativeB = NSApp.windows.first(where: { $0.title == "OCG cooperative B" }) else {
            throw ProbeError.nativeWindowUnavailable
        }
        nativeA.makeKeyAndOrderFront(nil)
        for _ in 0..<20 {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: nativeA.windowNumber, context: nil, characters: "a",
                charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
            ) else { throw ProbeError.incomplete }
            injectedAt = DispatchTime.now().uptimeNanoseconds
            NSApp.postEvent(event, atStart: false)
            try await waitUntil { injectedAt == nil }
        }
        print("WINDOW_COOPERATIVE events_finished")
        fflush(nil)

        taskA.cancel()
        do {
            try await taskA.value
            throw ProbeError.incomplete
        } catch is CancellationError {
        }
        guard nativeA.isVisible else { throw ProbeError.incomplete }
        let bBeforeCancellation = framesB
        b.viewsNeedDisplay = true
        try await waitUntil { framesB > bBeforeCancellation }
        b.viewsNeedDisplay = false
        taskA = Task { @MainActor in try await a.makeKeyAndOrderFrontAsync() }
        let aBeforeRestart = framesA
        a.viewsNeedDisplay = true
        try await waitUntil { framesA > aBeforeRestart }
        a.viewsNeedDisplay = false

        let closeStart = DispatchTime.now().uptimeNanoseconds
        nativeA.performClose(nil)
        try await taskA.value
        print("WINDOW_COOPERATIVE first_closed")
        fflush(nil)
        let closeMs = Double(DispatchTime.now().uptimeNanoseconds - closeStart) / 1_000_000
        let beforeB = framesB
        b.viewsNeedDisplay = true
        try await waitUntil { framesB > beforeB }
        b.viewsNeedDisplay = false
        taskB.cancel()
        do {
            try await taskB.value
            throw ProbeError.incomplete
        } catch is CancellationError {
        }
        guard nativeB.isVisible else { throw ProbeError.incomplete }
        print("WINDOW_COOPERATIVE cancelled")
        fflush(nil)
        let resumedB = Task { @MainActor in try await b.makeKeyAndOrderFrontAsync() }
        try await Task.sleep(for: .milliseconds(50))
        nativeB.performClose(nil)
        try await resumedB.value
        print("WINDOW_COOPERATIVE second_closed")
        fflush(nil)

        let elapsed = Double(end - start) / 1_000_000_000
        let cpu = cpuEnd - cpuStart
        print("WINDOW_COOPERATIVE idle_seconds=\(elapsed) idle_cpu_seconds=\(cpu) idle_cpu_percent_one_core=\(cpu / elapsed * 100)")
        print("WINDOW_COOPERATIVE events_posted=20 events_received=\(latencies.count) event_latency_ms=\(latencies)")
        print("WINDOW_COOPERATIVE frames_a=\(framesA) frames_b=\(framesB) idle_draws_a=\(idleDrawsA) idle_draws_b=\(idleDrawsB) task_during_loop=\(actorTaskRan) close_ms=\(closeMs) second_survived_close=true cancellation_kept_visible=true restart_closed=true")
        guard latencies.count == 20, cpu.isFinite else { throw ProbeError.incomplete }
        print("WINDOW_COOPERATIVE COMPLETE")
    }

    /// Waits cooperatively for a condition; the external supervisor enforces a hard deadline.
    @MainActor
    private static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else { throw ProbeError.incomplete }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Reads CPU time for the complete process.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}

/// Captures events routed to a GLFW-backed window.
@MainActor
private final class ProbeWindow: CGWindow {
    /// Receives events observed by the probe.
    var receivedEvent: (OpenCoreGraphics.CGEvent) -> Void = { _ in }

    /// Records an event delivered by GLFW.
    override func sendEvent(_ event: OpenCoreGraphics.CGEvent) {
        receivedEvent(event)
    }
}

/// An incomplete graphical experiment.
private enum ProbeError: Error {
    /// The AppKit host has not started processing its main event loop.
    case hostNotRunning
    /// One or more expected observations did not occur.
    case incomplete
    /// AppKit did not expose both native windows.
    case nativeWindowUnavailable
}
#else
/// Reports that this graphical experiment requires AppKit.
@main
private enum WindowCooperativeProbeUnavailable {
    /// Stops rather than claiming an unsupported measurement.
    static func main() {
        fatalError("The cooperative window probe requires a macOS graphical session.")
    }
}
#endif
