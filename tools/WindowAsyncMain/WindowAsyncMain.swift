#if os(macOS)
import AppKit
import Foundation
import OpenCoreGraphics
import OpenGLFW

/// Exercises the public window API from an ordinary asynchronous entry point.
@main
private struct WindowAsyncMain {
    /// Creates the first window without preinitializing AppKit or GLFW.
    @MainActor
    static func main() async throws {
        print("WINDOW_ASYNC_MAIN before_first_window")
        fflush(nil)
        if CommandLine.arguments.contains("--disable-menubar") {
            glfwInitHint(GLFW_COCOA_MENUBAR, GLFW_FALSE)
        }
        if CommandLine.arguments.contains("--disable-chdir") {
            glfwInitHint(GLFW_COCOA_CHDIR_RESOURCES, GLFW_FALSE)
        }
        if CommandLine.arguments.contains("--glfw-only") {
            guard glfwInit() != GLFW_FALSE else { throw ProbeError.incomplete }
            print("WINDOW_ASYNC_MAIN glfw_initialized")
            fflush(nil)
            var window: OpaquePointer?
            if CommandLine.arguments.contains("--glfw-window") {
                glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE)
                guard let created = glfwCreateWindow(240, 180, "GLFW", nil, nil) else {
                    throw ProbeError.incomplete
                }
                window = created
                print("WINDOW_ASYNC_MAIN glfw_window_created")
                fflush(nil)
            }
            try await Task.sleep(for: .milliseconds(200))
            print("WINDOW_ASYNC_MAIN GLFW_COMPLETE")
            fflush(nil)
            if let window { glfwDestroyWindow(window) }
            glfwTerminate()
            return
        }
        if CommandLine.arguments.contains("--initialization-failure") {
            do {
                _ = try OpenCoreGraphics.CGWindow(
                    frame: .init(x: 0, y: 0, width: 0, height: 180), title: "OCG invalid"
                )
                throw ProbeError.incomplete
            } catch CGWindowError.windowCreationFailed {
                print("WINDOW_ASYNC_MAIN initialization_error_observed")
                fflush(nil)
            }
            try await Task.sleep(for: .milliseconds(50))
            print("WINDOW_ASYNC_MAIN FAILURE_PATH_COMPLETE")
            fflush(nil)
            return
        }
        let a = try OpenCoreGraphics.CGWindow(
            frame: .init(x: 0, y: 0, width: 240, height: 180), title: "OCG async main A"
        )
        print("WINDOW_ASYNC_MAIN first_window_created")
        fflush(nil)
        if CommandLine.arguments.contains("--initialization-only") {
            try await Task.sleep(for: .milliseconds(200))
            print("WINDOW_ASYNC_MAIN INITIALIZATION_COMPLETE")
            fflush(nil)
            return
        }
        let b = try OpenCoreGraphics.CGWindow(
            frame: .init(x: 260, y: 0, width: 240, height: 180), title: "OCG async main B"
        )
        print("WINDOW_ASYNC_MAIN second_window_created")
        fflush(nil)
        var framesA = 0
        var framesB = 0
        a.display = {
            framesA += 1
            if framesA == 1 { print("WINDOW_ASYNC_MAIN first_frame_a"); fflush(nil) }
        }
        b.display = {
            framesB += 1
            if framesB == 1 { print("WINDOW_ASYNC_MAIN first_frame_b"); fflush(nil) }
        }
        let taskA = Task { @MainActor in try await a.makeKeyAndOrderFrontAsync() }
        let taskB = Task { @MainActor in try await b.makeKeyAndOrderFrontAsync() }
        defer { taskA.cancel(); taskB.cancel() }
        try await waitUntil { framesA >= 2 && framesB >= 2 }
        guard let nativeA = NSApp.windows.first(where: { $0.title == "OCG async main A" }),
              let nativeB = NSApp.windows.first(where: { $0.title == "OCG async main B" }) else {
            throw ProbeError.incomplete
        }
        taskA.cancel()
        do {
            try await taskA.value
            throw ProbeError.incomplete
        } catch is CancellationError {
        }
        guard nativeA.isVisible else { throw ProbeError.incomplete }
        let previousB = framesB
        try await waitUntil { framesB > previousB }
        let restarted = Task { @MainActor in try await a.makeKeyAndOrderFrontAsync() }
        defer { restarted.cancel() }
        let previousA = framesA
        try await waitUntil { framesA > previousA }
        nativeA.performClose(nil)
        try await restarted.value
        nativeB.performClose(nil)
        try await taskB.value
        print("WINDOW_ASYNC_MAIN COMPLETE frames_a=\(framesA) frames_b=\(framesB) cancelled_without_closing=true")
        fflush(nil)
    }

    /// Waits cooperatively while the external supervisor enforces a hard timeout.
    @MainActor
    private static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else { throw ProbeError.incomplete }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

/// Reports an incomplete async-main window experiment.
private enum ProbeError: Error {
    /// An expected observable state was not reached.
    case incomplete
}
#else
/// Reports that this AppKit-based probe is not available on this platform.
@main
private enum WindowAsyncMainUnavailable {
    /// Stops instead of reporting an unperformed test as successful.
    static func main() {
        fatalError("The async-main window probe requires a macOS graphical session.")
    }
}
#endif
