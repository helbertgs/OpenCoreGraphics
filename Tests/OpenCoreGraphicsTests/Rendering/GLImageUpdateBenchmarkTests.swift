import Foundation
import Testing
@testable import OpenCoreGraphics

@MainActor
struct GLImageUpdateBenchmarkTests {
    /// Compares the reusable cache with direct allocation for identical static and mutable snapshots.
    @Test
    func measuresStaticAndMutableImageUpdateCosts() throws {
        let frameCount = 30
        let width = 128
        let height = 128
        let frameBytes = width * height * 4
        let repetitions = 7
        let workloads = [
            ("static", try captureFrames(count: frameCount, width: width, height: height, changing: false)),
            ("mutable", try captureFrames(count: frameCount, width: width, height: height, changing: true))
        ]

        for (scenario, workload) in workloads {
            let frames = workload.frames
            #expect(workload.captureCount == frameCount)
            #expect(workload.capturedSourceBytes == frameCount * frameBytes)
            #expect(frames.allSatisfy { $0.identity == frames[0].identity })
            if scenario == "mutable" {
                #expect(frames.first?.data != frames.last?.data)
            } else {
                #expect(frames.allSatisfy { $0.data == frames[0].data })
            }
            let warmupCache = try runCached(frames: frames, frameBytes: frameBytes)
            let warmupReference = try runReference(frames: frames, frameBytes: frameBytes)
            #expect(warmupCache.uploadCalls == 1)
            #expect(warmupCache.updateCalls == (scenario == "static" ? 0 : frameCount - 1))
            #expect(warmupReference.uploadCalls == frameCount)

            var cachedSamples: [Double] = []
            var referenceSamples: [Double] = []
            var cachedMetrics: BenchmarkPassMetrics?
            var referenceMetrics: BenchmarkPassMetrics?
            for _ in 0..<repetitions {
                let cached = try runCached(frames: frames, frameBytes: frameBytes)
                let reference = try runReference(frames: frames, frameBytes: frameBytes)
                cachedSamples.append(cached.elapsedNanoseconds)
                referenceSamples.append(reference.elapsedNanoseconds)
                cachedMetrics = cached
                referenceMetrics = reference
            }

            let cached = try #require(cachedMetrics)
            let reference = try #require(referenceMetrics)
            #expect(cached.uploadCalls == 1)
            #expect(cached.updateCalls == (scenario == "static" ? 0 : frameCount - 1))
            #expect(cached.comparisonCalls == frameCount - 1)
            #expect(reference.uploadCalls == frameCount)
            #expect(reference.updateCalls == 0)
            #expect(reference.comparisonCalls == 0)
            #expect(cached.uploadedBytes == (scenario == "static" ? frameBytes : frameBytes * frameCount))
            #expect(reference.uploadedBytes == frameBytes * frameCount)
            #expect(cached.logicalCacheBytes == frameBytes * 2)
            #expect(reference.logicalCacheBytes == 0)
            #expect(reference.peakTextureBytes == frameBytes)
            #expect(cached.lastPayload == frames.last?.data)
            #expect(reference.lastPayload == frames.last?.data)

            let reportJSON = try report(
                scenario: scenario,
                width: width,
                height: height,
                frames: frameCount,
                repetitions: repetitions,
                snapshotCaptureCount: workload.captureCount,
                snapshotCopiedBytes: workload.capturedSourceBytes,
                snapshotCaptureDuration: workload.captureNanoseconds,
                cached: cached,
                reference: reference,
                cachedMedian: median(cachedSamples),
                referenceMedian: median(referenceSamples)
            )
            print("IMAGE_UPDATE_BENCHMARK: \(reportJSON)")
        }
    }

    /// Captures deterministic image frames through the production CGImage snapshot initializer.
    /// - Parameters:
    ///   - count: The number of immutable snapshots.
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - changing: Whether successive snapshots contain changed bytes.
    /// - Returns: Production snapshots and the measured source-copy metrics.
    private func captureFrames(
        count: Int,
        width: Int,
        height: Int,
        changing: Bool
    ) throws -> (frames: [CGImageSnapshot], captureCount: Int, capturedSourceBytes: Int, captureNanoseconds: Double) {
        let byteCount = width * height * 4
        let frameData = (0..<count).map { frame in
            var data = Data(repeating: 127, count: byteCount)
            if changing {
                data[byteCount - 2] = frame.isMultiple(of: 2) ? 126 : 128
            }
            return data
        }
        let provider = CGDataProvider(data: frameData[0])
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        let clock = ContinuousClock()
        var frames: [CGImageSnapshot] = []
        frames.reserveCapacity(count)
        let start = clock.now
        for data in frameData {
            provider.data = data
            frames.append(CGImageSnapshot(image: image))
        }
        let captureNanoseconds = nanoseconds(in: start.duration(to: clock.now))
        return (frames, frames.count, count * byteCount, captureNanoseconds)
    }

    /// Measures the actual cache logic with a no-op texture backend.
    /// - Parameters:
    ///   - frames: The input snapshots shared with the reference.
    ///   - frameBytes: Logical RGBA8 bytes per image.
    /// - Returns: Cache operation counts, uploaded bytes, retained bytes and elapsed time.
    private func runCached(frames: [CGImageSnapshot], frameBytes: Int) throws -> BenchmarkPassMetrics {
        let loader = ImageBenchmarkLoader()
        let cache = GLTextureCache(loader: loader)
        let clock = ContinuousClock()
        let start = clock.now
        for frame in frames {
            _ = try cache.texture(for: frame)
        }
        let elapsed = nanoseconds(in: start.duration(to: clock.now))
        let retainedBytes = cache.retainedByteCount
        cache.byteBudget = 0
        return BenchmarkPassMetrics(
            uploadCalls: loader.uploadCalls,
            updateCalls: loader.updateCalls,
            comparisonCalls: max(0, frames.count - loader.uploadCalls),
            uploadedBytes: loader.uploadedBytes,
            logicalCacheBytes: retainedBytes,
            peakTextureBytes: frameBytes,
            lastPayload: loader.lastPayload,
            elapsedNanoseconds: elapsed
        )
    }

    /// Measures a direct allocate-per-frame reference with no texture reuse.
    /// - Parameters:
    ///   - frames: The same snapshots passed to the cache measurement.
    ///   - frameBytes: Logical RGBA8 bytes per image.
    /// - Returns: Upload counts, bytes, transient texture size and elapsed time.
    private func runReference(frames: [CGImageSnapshot], frameBytes: Int) throws -> BenchmarkPassMetrics {
        let loader = ImageBenchmarkLoader()
        let clock = ContinuousClock()
        let start = clock.now
        for frame in frames {
            let texture = try loader.makeTexture(from: frame)
            withExtendedLifetime(texture) {}
        }
        let elapsed = nanoseconds(in: start.duration(to: clock.now))
        return BenchmarkPassMetrics(
            uploadCalls: loader.uploadCalls,
            updateCalls: loader.updateCalls,
            comparisonCalls: 0,
            uploadedBytes: loader.uploadedBytes,
            logicalCacheBytes: 0,
            peakTextureBytes: frameBytes,
            lastPayload: loader.lastPayload,
            elapsedNanoseconds: elapsed
        )
    }

    /// Encodes the input conditions and observed metrics as one stable JSON line.
    /// - Parameters:
    ///   - scenario: Whether the workload is static or mutating.
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - frames: Number of immutable snapshots in the workload.
    ///   - repetitions: Number of timed passes per strategy.
    ///   - snapshotCaptureCount: Number of production CGImage snapshot captures.
    ///   - snapshotCopiedBytes: Source payload bytes captured through the production path.
    ///   - snapshotCaptureDuration: Time spent in the production snapshot capture loop.
    ///   - cached: Last cache-path measurement.
    ///   - reference: Last no-reuse measurement.
    ///   - cachedMedian: Median cache-path duration.
    ///   - referenceMedian: Median reference duration.
    /// - Returns: The benchmark report as sorted JSON.
    /// - Throws: An error if JSON serialization or UTF-8 conversion fails.
    private func report(
        scenario: String,
        width: Int,
        height: Int,
        frames: Int,
        repetitions: Int,
        snapshotCaptureCount: Int,
        snapshotCopiedBytes: Int,
        snapshotCaptureDuration: Double,
        cached: BenchmarkPassMetrics,
        reference: BenchmarkPassMetrics,
        cachedMedian: Double,
        referenceMedian: Double
    ) throws -> String {
        let values: [String: Any] = [
            "scenario": scenario,
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": architecture,
            "width": width,
            "height": height,
            "frames": frames,
            "repetitions": repetitions,
            "productionSnapshotCaptureCalls": snapshotCaptureCount,
            "productionSnapshotSourceBytes": snapshotCopiedBytes,
            "productionSnapshotCaptureNanoseconds": Int(snapshotCaptureDuration.rounded()),
            "explicitSnapshotCopyOperations": snapshotCaptureCount,
            "explicitSnapshotCopiedBytes": snapshotCopiedBytes,
            "explicitSnapshotCopy": "CGImageSnapshot.init(image:) performs Data(Array(provider.data))",
            "cached": cached.dictionary,
            "referenceNoReuse": reference.dictionary,
            "cachedMedianNanoseconds": Int(cachedMedian.rounded()),
            "referenceMedianNanoseconds": Int(referenceMedian.rounded()),
            "memoryMeasurement": "logical cache/texture bytes; excludes process RSS"
        ]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ImageUpdateBenchmarkError.reportEncodingFailed
        }
        return json
    }

    /// Returns the compilation architecture for the benchmark environment record.
    private var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "other"
        #endif
    }

    /// Converts a monotonic duration to nanoseconds.
    /// - Parameter duration: The measured monotonic duration.
    /// - Returns: The duration in nanoseconds.
    private func nanoseconds(in duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
    }

    /// Calculates the median of one or more measured values.
    /// - Parameter values: The measured nanosecond durations.
    /// - Returns: The median duration in nanoseconds.
    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

/// Errors raised when benchmark results cannot be encoded for reproducible reporting.
private enum ImageUpdateBenchmarkError: Error {
    /// JSON serialization did not produce valid UTF-8.
    case reportEncodingFailed
}

/// Metrics recorded by one pass of the deterministic image workload.
private struct BenchmarkPassMetrics {
    /// Number of image payloads passed to the loader's create operation.
    let uploadCalls: Int
    /// Number of image payloads passed to the loader's update operation.
    let updateCalls: Int
    /// Number of cache content equality decisions on existing identities.
    let comparisonCalls: Int
    /// Total source bytes passed to create or update operations.
    let uploadedBytes: Int
    /// Logical bytes retained by the cache after all frames are processed.
    let logicalCacheBytes: Int
    /// Maximum logical size of one transient RGBA8 texture.
    let peakTextureBytes: Int
    /// Last payload submitted to the fake loader for pixel-preservation checks.
    let lastPayload: Data?
    /// Elapsed monotonic time for the complete frame loop, in nanoseconds.
    let elapsedNanoseconds: Double

    /// Returns the metrics as a JSON-compatible dictionary.
    var dictionary: [String: Int] {
        [
            "uploadCalls": uploadCalls,
            "updateCalls": updateCalls,
            "comparisonCalls": comparisonCalls,
            "uploadedBytes": uploadedBytes,
            "logicalCacheBytes": logicalCacheBytes,
            "peakTextureBytes": peakTextureBytes,
            "elapsedNanoseconds": Int(elapsedNanoseconds.rounded())
        ]
    }
}

/// A texture loader that records upload operations without requiring an OpenGL context.
@MainActor
private final class ImageBenchmarkLoader: GLTextureLoader {
    /// Number of image payloads sent to create.
    private(set) var uploadCalls = 0
    /// Number of image payloads sent to update.
    private(set) var updateCalls = 0
    /// Total source bytes passed to create and update.
    private(set) var uploadedBytes = 0
    /// Most recent image pixel payload sent to the loader.
    private(set) var lastPayload: Data?
    /// The next unique fake texture identifier.
    private var nextIdentifier: UInt32 = 1

    /// Records a texture allocation and its pixel payload.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture {
        uploadCalls += 1
        uploadedBytes += image.data?.count ?? 0
        lastPayload = image.data
        let identifier = nextIdentifier
        nextIdentifier += 1
        return GLTexture(identifier: identifier, width: image.width, height: image.height) { _ in }
    }

    /// Creates a placeholder texture for protocol completeness.
    func makeTexture(from glyphAtlas: CGGlyphAtlas) throws -> GLTexture {
        let identifier = nextIdentifier
        nextIdentifier += 1
        return GLTexture(identifier: identifier, width: glyphAtlas.width, height: glyphAtlas.height) { _ in }
    }

    /// Records an update to an existing texture.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws {
        updateCalls += 1
        uploadedBytes += image.data?.count ?? 0
        lastPayload = image.data
    }
}
