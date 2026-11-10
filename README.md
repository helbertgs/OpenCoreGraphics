# OpenCoreGraphics

The OpenCoreGraphics framework is based on the Apple's CoreGraphics advanced drawing engine. It provides low-level, lightweight 2D rendering with unmatched output fidelity. 
You use this framework to handle path-based drawing, transformations, color management, offscreen rendering, patterns, gradients and shadings, image data management, image creation, and image masking, display, and parsing.

In Windows and Linux, OpenCoreGraphics also includes services for working with display hardware, low-level user input events, and the windowing system.

# Tech Stack

- Swift 6.4+
- OpenGL 3.3

# Project Structure

- **Sources/OpenCoreGraphics**: The framework code base.
- **Sources/OpenCoreGraphicsSample**: The sample app used to draw shapes in the window.
- **Tests/OpenCoreGraphicsTests**: Unit tests

# Commands

- **Build**: swift build
- **Test**: swift test
- **Run the Sample**: swift run
- **Run the opt-in OpenGL comparisons**: `ruby scripts/run-gl-tests.rb --timeout 120` on a machine with a graphical session and an OpenGL 3.3 driver. The timeout covers the build and tests. The runner exits with 0 only when both comparisons complete successfully; 1 means a failure, timeout, interruption, skipped test or incomplete report, and 2 means invalid arguments or an explicitly reported unavailable graphics context. Ruby and Swift must be available on `PATH`. Each run prints a unique artifacts directory under `.build/gl-comparison/` (override the parent directory with `OPENCOREGRAPHICS_GL_ARTIFACTS`): per-scene JSON contains the system, GL driver, framebuffer state, tolerance and result; failing scenes also preserve raw RGBA pixel buffers for both backends. Comparisons normalize opaque framebuffer pixels to sRGB; see [GL comparison diagnostics](.docs/GLComparisonDiagnostics.md). Incomplete runs may contain only partial results and must not be interpreted as passing.

## Cooperative window processing

`CGWindow.makeKeyAndOrderFrontAsync(_:)` is a `@MainActor` asynchronous alternative
to the existing blocking `makeKeyAndOrderFront(_:)`. Calls for different windows
share a GLFW event pump. Keep `viewsNeedDisplay` true for continuous animation;
set it to false after a static frame and back to true to request another one.
Cancelling the task throws `CancellationError` and stops that window's
participation **without closing it**. Arrange another event pump or explicitly
close the window afterward.

**macOS host prerequisite:** for the validated standalone integration, start
`NSApplication.run()` from a synchronous `main`, and create the windows inside
a `@MainActor` task after the AppKit loop is running. The host owns that loop
and its shutdown; the library does not install a hidden bootstrap. See the
complete, executable example in
[`tools/WindowCooperative/WindowCooperativeProbe.swift`](tools/WindowCooperative/WindowCooperativeProbe.swift)
and run it with `ruby scripts/run-window-cooperative.rb --timeout 60`.

An ordinary standalone `async main` without this host can exit successfully
before its task finishes; this remains unresolved. The host pattern above is
the integration exercised here, not a guarantee for other AppKit application
lifecycles. A zero exit status alone is not evidence of completion.

The cooperative pump checks for work on a timer, so redraw is not immediate.
GLFW requires the OS main thread; a `MainActor` executor is not by itself a
portable guarantee of that thread. Duplicate participation and detected GLFW
context/thread failures throw errors. Avoid mixing this pump with the blocking
window loop or another GLFW event loop. Platform, startup, error, and performance
limitations and the supervised graphical experiment are documented in
[WindowLoopCooperative.md](.docs/WindowLoopCooperative.md).