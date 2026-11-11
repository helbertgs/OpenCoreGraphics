# OpenCoreGraphics

OpenCoreGraphics is a Swift 2D drawing framework with path-based drawing,
transformations, color management, bitmap rendering, images, text, gradients,
and window-backed rendering. Its behavior and limitations are documented from
the current implementation; it does not claim complete Core Graphics
compatibility.

# Tech Stack

- Swift 6.4+
- OpenGL 3.3

The package manifest declares macOS 13 as its minimum platform. The documented
build, test, and graphical results are from macOS; this repository does not
currently run CI for Windows or Linux, and this README makes no claim that
those platforms have been validated.

# Project Structure

- **Sources/OpenCoreGraphics**: The framework code base.
- **Sources/OpenCoreGraphicsSample**: The sample app used to draw shapes in the window.
- **Tests/OpenCoreGraphicsTests**: Unit tests

# Commands

- **Build**: swift build
- **Test**: swift test
- **Run the Sample**: swift run
- **Strict-concurrency build and tests**:
  `swift build -Xswiftc -strict-concurrency=complete` and
  `swift test -Xswiftc -strict-concurrency=complete`
- **Run the opt-in OpenGL comparisons**: `ruby scripts/run-gl-tests.rb --timeout 120` on a machine with a graphical session and an OpenGL 3.3 driver. The timeout covers the build and tests. The runner exits with 0 only when both comparisons complete successfully; 1 means a failure, timeout, interruption, skipped test or incomplete report, and 2 means invalid arguments or an explicitly reported unavailable graphics context. Ruby and Swift must be available on `PATH`. Each run prints a unique artifacts directory under `.build/gl-comparison/` (override the parent directory with `OPENCOREGRAPHICS_GL_ARTIFACTS`): per-scene JSON contains the system, GL driver, framebuffer state, tolerance and result; failing scenes also preserve raw RGBA pixel buffers for both backends. Comparisons normalize opaque framebuffer pixels to sRGB; see [GL comparison diagnostics](.docs/GLComparisonDiagnostics.md). Incomplete runs may contain only partial results and must not be interpreted as passing.
- **macOS automation**: GitHub Actions selects an installed Swift 6.4-or-later toolchain or fails explicitly, then runs build, standard tests and complete strict-concurrency checks on `macos-26`; fixture tests exercise toolchain selection before using a real compiler. GL comparisons are disabled unless manually requested on a configured self-hosted graphics runner. Test skips and the absence of coverage reporting are explicit in the job summary. See [macOS automation details](.docs/CI.md).

The standard `swift test` command does not opt into the real-GL suites. Those
comparisons require a usable graphical session and driver; a skipped, timed-out,
or incomplete run is not a pass. The local runner reports these conditions
separately instead of treating a zero child-process exit by itself as success.

## Loading a font

`CGFont.init?(_:)` takes a filesystem path to a TrueType font file, not a
PostScript name or family name. It returns `nil` when the path cannot be read or
the file cannot be parsed; it does not search installed fonts:

```swift
guard let font = CGFont("/System/Library/Fonts/Supplemental/Arial.ttf") else {
    // Handle a missing, unreadable, or unsupported font file.
    return
}
context.setFont(font)
```

The initializer reads and parses the file immediately and keeps its font data
with the `CGFont` instance; it does not need to reopen the path for later text
drawing. A graphics state retains its selected font while saved and restores
that font with `restoreGState()`. `CGFont` does not conform to `Sendable`; do
not share a font or mutable graphics context concurrently.

In the versioned sample, text drawing is enabled by default. Its text helper
uses `--font` as a TrueType file-path override. On macOS systems where the
sample's bundled fallback path exists, for example:

```sh
swift run OpenCoreGraphicsSample --font /System/Library/Fonts/Supplemental/Arial.ttf
```

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

## Glyph-cache measurements

Run the deterministic CPU prototype comparison with
`swift test -Xswiftc -strict-concurrency=complete --filter GLGlyphCacheBenchmarkTests`.
The comparison covers repeated static and changing text, reports rasterization,
upload-model, preparation-time and logical-memory measurements, and does not
call OpenGL for the prototype strategies. The current pipeline's separate GL
timings and the latest run-to-run measurement changes are documented in
[glyph benchmark methodology and results](.docs/GlyphCacheBenchmark.md).
These measurements do not justify a production glyph cache or establish a
performance gain. The conclusive GL runner separately validates text rendering
across glyph pages.

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

## Implementation guides and limits

The guides below describe the current implementation; “not implemented” is a
limitation, not a promise of future support:

- [Rendering concurrency](.docs/RenderingConcurrency.md): bitmap ownership,
  caller-provided buffer lifetime, exclusive access, actor isolation, image
  snapshots, and texture-cache accounting.
- [Cooperative window processing](.docs/WindowLoopCooperative.md) and
  [loop strategy](.docs/WindowLoopStrategy.md): async window lifecycle,
  cancellation, host prerequisites, polling latency, and known limitations.
- [Gradients](.docs/Gradients.md): software and OpenGL rendering paths,
  interpolation and extension behavior. Both paths are implemented, but the
  general GL comparison suite does not establish parity for every gradient.
- [Shadows](.docs/ShadowRendering.md): supported by the software renderer;
  OpenGL does not implement the blur pass and draws the shape without its
  shadow.
- [GL blend mapping](.docs/GLBlendModeMapping.md): direct OpenGL mappings and
  modes that currently fall back to normal source-over.
- [Image-cache measurements](.docs/ImageUpdateBenchmark.md) and
  [glyph measurements](.docs/GlyphCacheBenchmark.md): measured cache
  bookkeeping and prototype models, with explicit boundaries on GPU timing and
  performance claims.
- [Static-analysis checks](.docs/StaticAnalysis.md),
  [coverage scope](.docs/tasks/coverage.md), and
  [macOS automation](.docs/CI.md): reproducible checks, exclusions, and
  platform scope.