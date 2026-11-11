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

The GL runner also requires one valid `GL_GLYPH_PAGING` result. The paged
glyph comparison checks mean difference across the whole framebuffer and
separately compares pixels in the horizontal regions before and after the
page boundary. Both GL and software regions must contain non-black glyph
pixels, the run must report more than one page, and both regional differences
must remain within the glyph tolerance. A missing, duplicate, malformed, or
failing marker makes the GL run fail.

## Image update measurements

Run the deterministic CPU-side image-cache workload with
`swift test -Xswiftc -strict-concurrency=complete --filter GLImageUpdateBenchmarkTests`.
It prints same-input comparisons for static and changing 128×128 RGBA images,
captured per frame through the production `CGImageSnapshot(image:)` path,
including explicit snapshot payload copies, cache equality checks, texture-loader
calls, uploaded bytes, elapsed time and logical retained bytes. The recording
loader does not call OpenGL, so these measurements characterize cache bookkeeping
and upload decisions—not GPU transfer latency, process RSS or rendered pixels.
See [image update benchmark methodology and results](.docs/ImageUpdateBenchmark.md).

## OpenGL glyph texture limits

Window text rendering reads `GL_MAX_TEXTURE_SIZE` only after selecting the
window's owning OpenGL context. A text command is divided into consecutive
glyph pages; each page includes the existing transparent glyph gutters and
stays within the queried width and height. Pages are drawn in source order,
and character spacing continues to use each glyph's original text index.
The software renderer keeps the complete command and does not depend on the
device limit.

A glyph whose padded bitmap cannot fit, an invalid reported limit, a zero
texture identifier, or an OpenGL texture-upload error is retained as a typed
`WindowRenderTargetError.renderingFailed` on the window render target and is
written to standard error. Since the existing `CGContext.flush()` API is
nonthrowing, it is not changed. The error is terminal for that render target:
later submissions are discarded, readback fails, and resize barriers are not
applied. Creating a new window render target is the recovery boundary; the
target does not retry a partially rendered text command automatically.
Commands consumed before a failed resize barrier are removed from every later
barrier's pending-command count, preserving queue invariants. GL errors already
pending before the texture storage call are reported separately from errors
raised by the upload itself. These errors describe GPU texture
allocation/upload; they cannot recover from process-level CPU memory exhaustion
while rasterizing or assembling an exceptionally large text command.

The real-GL glyph paging scenario deliberately places visible glyphs on both
sides of the page boundary. Its report records non-black pixel counts for GL
and software independently in each region and their local mean differences,
in addition to the whole-frame mean. This rejects an all-black frame and
localized errors on the second page even when a global average would hide them.

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