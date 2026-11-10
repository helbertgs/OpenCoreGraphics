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
- **Run the opt-in OpenGL comparisons**: `ruby scripts/run-gl-tests.rb --timeout 120` on a machine with a graphical session and an OpenGL 3.3 driver. The timeout covers the build and tests. The runner exits with 0 only when both comparisons complete successfully; 1 means a failure, timeout, interruption, skipped test or incomplete report, and 2 means invalid arguments or an explicitly reported unavailable graphics context. Ruby and Swift must be available on `PATH`. Each run prints a unique artifacts directory under `.build/gl-comparison/` (override the parent directory with `OPENCOREGRAPHICS_GL_ARTIFACTS`): per-scene JSON contains the system, GL driver, framebuffer state, tolerance and result; failing scenes also preserve raw RGBA pixel buffers for both backends. Incomplete runs may contain only partial results and must not be interpreted as passing.