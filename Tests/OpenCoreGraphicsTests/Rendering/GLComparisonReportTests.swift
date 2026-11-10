import Foundation
import Testing

/// Verifies comparison reports without requiring a graphics context.
struct GLComparisonReportTests {
    /// Simulated driver state for deterministic report tests.
    private let metadata = GLComparisonReport.Metadata(
        system: "test OS", version: "3.3", renderer: "test renderer", vendor: "test vendor",
        encoding: "sRGB", sRGBEnabled: true, sampleBuffers: 1, samples: 4, multisampleEnabled: true,
        readFramebuffer: 0, drawFramebuffer: 0, readBuffer: 1029, viewport: [0, 0, 1, 1]
    )

    /// Records a failing scene and retains both original pixel buffers.
    @Test
    private func failureWritesMetadataAndPixels() throws {
        let output = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: output) } }
        let gl = Data([1, 2, 3, 4])
        let software = Data([4, 3, 2, 1])
        _ = try GLComparisonReport(
            scene: "rectangle", width: 1, height: 1, difference: 0.1, tolerance: 0.01,
            glPixels: gl, softwarePixels: software, metadata: metadata, output: output
        )
        let json = try Data(contentsOf: output.appending(path: "rectangle.json"))
        let report = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(report["status"] as? String == "failed")
        #expect(report["glRenderer"] as? String == "test renderer")
        #expect(report["samples"] as? Int == 4)
        #expect(report["framebufferWidth"] as? Int == 1)
        #expect(report["viewport"] as? [Int] == [0, 0, 1, 1])
        #expect(report["difference"] as? Double == 0.1)
        #expect(try Data(contentsOf: output.appending(path: "rectangle-gl.rgba")) == gl)
        #expect(try Data(contentsOf: output.appending(path: "rectangle-software.rgba")) == software)
    }

    /// Does not write failure artifacts for a passing scene.
    @Test
    private func passingSceneHasNoPixelArtifacts() throws {
        let output = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: output) } }
        let pixels = Data([0, 0, 0, 255])
        _ = try GLComparisonReport(
            scene: "image", width: 1, height: 1, difference: 0, tolerance: 0.01,
            glPixels: pixels, softwarePixels: pixels, metadata: metadata, output: output
        )
        let json = try Data(contentsOf: output.appending(path: "image.json"))
        let report = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(report["status"] as? String == "passed")
        #expect(FileManager.default.fileExists(atPath: output.appending(path: "image-gl.rgba").path) == false)
    }

    /// Rejects unsafe scene names and mismatched pixel storage.
    @Test
    private func invalidInputsAreRejected() throws {
        let output = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let pixels = Data([0, 0, 0, 255])
        #expect(throws: GLComparisonReportError.invalidSceneName) {
            try GLComparisonReport(
                scene: "../escape", width: 1, height: 1, difference: 0, tolerance: 0,
                glPixels: pixels, softwarePixels: pixels, metadata: metadata, output: output
            )
        }
        #expect(throws: GLComparisonReportError.invalidComparison) {
            try GLComparisonReport(
                scene: "bad", width: 2, height: 1, difference: 0, tolerance: 0,
                glPixels: pixels, softwarePixels: pixels, metadata: metadata, output: output
            )
        }
        #expect(FileManager.default.fileExists(atPath: output.path) == false)
    }

    /// Propagates an error when the requested output directory cannot be created.
    @Test
    private func filesystemFailureIsReported() throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data([1]).write(to: parent)
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: parent) } }
        let pixels = Data([0, 0, 0, 255])
        #expect(throws: (any Error).self) {
            try GLComparisonReport(
                scene: "rectangle", width: 1, height: 1, difference: 0, tolerance: 0,
                glPixels: pixels, softwarePixels: pixels, metadata: metadata,
                output: parent.appending(path: "nested")
            )
        }
    }
}
