import Foundation
@preconcurrency import OpenGLAD

/// Identifies invalid graphics state or input that prevents a reliable comparison report.
enum GLComparisonReportError: Error, Equatable {
    /// The scene name cannot safely be used as an artifact filename.
    case invalidSceneName
    /// The framebuffer buffer or color encoding could not be determined.
    case unknownFramebufferEncoding
    /// The driver did not provide the requested implementation information.
    case missingDriverInformation
    /// OpenGL reported an error while drawing, reading pixels or querying metadata.
    case graphicsError(UInt32)
    /// The dimensions, pixel buffers, difference or tolerance are invalid.
    case invalidComparison
}

/// Records a comparison and preserves the original framebuffer bytes for failed scenes.
struct GLComparisonReport {
    /// Captures the graphics driver and framebuffer settings relevant to pixel comparison.
    struct Metadata {
        /// Operating system version.
        let system: String
        /// OpenGL implementation version.
        let version: String
        /// Graphics renderer name.
        let renderer: String
        /// Graphics driver vendor.
        let vendor: String
        /// Whether the framebuffer uses sRGB or linear encoding.
        let encoding: String
        /// Whether OpenGL converts output to sRGB.
        let sRGBEnabled: Bool
        /// The number of multisample buffers.
        let sampleBuffers: Int32
        /// The number of samples in the active framebuffer.
        let samples: Int32
        /// Whether multisample rasterization is enabled.
        let multisampleEnabled: Bool
        /// Framebuffer selected for reading.
        let readFramebuffer: Int32
        /// Framebuffer selected for drawing.
        let drawFramebuffer: Int32
        /// The buffer selected for reading.
        let readBuffer: Int32
        /// OpenGL viewport as x, y, width and height.
        let viewport: [Int32]
    }

    /// Captures the active GL state and writes the result of a scene comparison.
    /// - Parameters:
    ///   - scene: A stable name for the scene.
    ///   - width: The framebuffer width in pixels.
    ///   - height: The framebuffer height in pixels.
    ///   - difference: Mean normalized channel difference.
    ///   - tolerance: Maximum permitted mean difference.
    ///   - glPixels: Bottom-up RGBA bytes read from the framebuffer.
    ///   - softwarePixels: Bitmap bytes produced by the software renderer.
    /// - Throws: An error when the OpenGL metadata or output files cannot be obtained.
    @MainActor
    init(
        scene: String,
        width: Int,
        height: Int,
        difference: Double,
        tolerance: Double,
        glPixels: Data,
        softwarePixels: Data
    ) throws {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_GL_ARTIFACTS"]
            ?? ".build/gl-comparison", isDirectory: true)
        var sampleBuffers: GLint = 0
        var samples: GLint = 0
        var drawFramebuffer: GLint = 0
        var viewport: [GLint] = [0, 0, 0, 0]
        let framebuffer = try GLComparisonFramebuffer()
        glad_glGetIntegerv(GLenum(GL_SAMPLE_BUFFERS), &sampleBuffers)
        glad_glGetIntegerv(GLenum(GL_SAMPLES), &samples)
        glad_glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &drawFramebuffer)
        glad_glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        guard let version = glad_glGetString(GLenum(GL_VERSION)),
              let renderer = glad_glGetString(GLenum(GL_RENDERER)),
              let vendor = glad_glGetString(GLenum(GL_VENDOR)) else {
            throw GLComparisonReportError.missingDriverInformation
        }
        let glError = glad_glGetError()
        guard glError == GLenum(GL_NO_ERROR) else {
            throw GLComparisonReportError.graphicsError(glError)
        }
        let metadata = Metadata(
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            version: String(cString: version),
            renderer: String(cString: renderer),
            vendor: String(cString: vendor),
            encoding: framebuffer.encoding == GLint(GL_SRGB) ? "sRGB" : "linear",
            sRGBEnabled: glad_glIsEnabled(GLenum(GL_FRAMEBUFFER_SRGB)) == GL_TRUE,
            sampleBuffers: sampleBuffers,
            samples: samples,
            multisampleEnabled: glad_glIsEnabled(GLenum(GL_MULTISAMPLE)) == GL_TRUE,
            readFramebuffer: framebuffer.readFramebuffer,
            drawFramebuffer: drawFramebuffer,
            readBuffer: framebuffer.readBuffer,
            viewport: viewport
        )
        try self.init(
            scene: scene, width: width, height: height, difference: difference, tolerance: tolerance,
            glPixels: glPixels, softwarePixels: softwarePixels, metadata: metadata, output: output
        )
    }

    /// Writes a scene result and its metadata, retaining both pixel buffers on failure.
    /// - Parameters:
    ///   - scene: A filename-safe scene identifier.
    ///   - width: The framebuffer width.
    ///   - height: The framebuffer height.
    ///   - difference: Mean normalized channel difference.
    ///   - tolerance: Maximum permitted mean difference.
    ///   - glPixels: Bytes read from OpenGL.
    ///   - softwarePixels: Bytes read from the software renderer.
    ///   - metadata: Driver and framebuffer information.
    ///   - output: The directory for this run's artifacts.
    /// - Throws: An error when inputs or filesystem operations are invalid.
    init(
        scene: String,
        width: Int,
        height: Int,
        difference: Double,
        tolerance: Double,
        glPixels: Data,
        softwarePixels: Data,
        metadata: Metadata,
        output: URL
    ) throws {
        guard scene.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw GLComparisonReportError.invalidSceneName
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, !pixelOverflow, !byteOverflow,
              glPixels.count == byteCount, softwarePixels.count == byteCount,
              difference.isFinite, tolerance.isFinite, difference >= 0, tolerance >= 0 else {
            throw GLComparisonReportError.invalidComparison
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let failed = difference > tolerance
        let report: [String: Any] = [
            "scene": scene,
            "status": failed ? "failed" : "passed",
            "system": metadata.system,
            "glVersion": metadata.version,
            "glRenderer": metadata.renderer,
            "glVendor": metadata.vendor,
            "framebufferWidth": width,
            "framebufferHeight": height,
            "framebufferEncoding": metadata.encoding,
            "framebufferSRGBEnabled": metadata.sRGBEnabled,
            "sampleBuffers": metadata.sampleBuffers,
            "samples": metadata.samples,
            "multisampleEnabled": metadata.multisampleEnabled,
            "readFramebuffer": metadata.readFramebuffer,
            "drawFramebuffer": metadata.drawFramebuffer,
            "readBuffer": metadata.readBuffer,
            "viewport": metadata.viewport,
            "difference": difference,
            "tolerance": tolerance,
            "pixelFormat": "RGBA8, bottom-up rows",
            "comparisonColorSpace": "sRGB, opaque RGBA"
        ]
        if failed {
            try glPixels.write(to: output.appending(path: "\(scene)-gl.rgba"), options: .atomic)
            try softwarePixels.write(to: output.appending(path: "\(scene)-software.rgba"), options: .atomic)
        }
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: output.appending(path: "\(scene).json"), options: .atomic)
        print("GL_COMPARISON: \(scene) \(failed ? "FAILED" : "PASSED") difference=\(difference) tolerance=\(tolerance)")
    }
}
