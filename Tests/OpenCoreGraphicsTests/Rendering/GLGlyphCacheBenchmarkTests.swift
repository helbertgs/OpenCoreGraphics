import Foundation
import Testing
@testable import OpenCoreGraphics

/// Compares per-command glyph atlases with controlled cache prototypes.
@MainActor
struct GLGlyphCacheBenchmarkTests {
    /// Measures deterministic static and mutable text workloads and emits JSON metrics.
    @Test
    func measuresRepeatedAndMutableGlyphWorkloads() throws {
        let frameCount = 30
        let glyphsPerFrame = 48
        let fontSize = 20.0
        let pageSize = 64
        let repetitions = 7
        let font = try sampleFont()
        let staticText = String(repeating: "IA", count: glyphsPerFrame / 2)
        let staticFrames = try makeFrames(staticText, count: frameCount, font: font)
        let mutableTexts = (0..<frameCount).map { frame in
            String(repeating: "IA", count: glyphsPerFrame / 2 - 1)
                + (frame.isMultiple(of: 2) ? "IA" : "AI")
        }
        let mutableFrames = try mutableTexts.map { try glyphs(in: $0, font: font) }

        #expect(staticFrames.count == frameCount)
        #expect(staticFrames.allSatisfy { $0 == staticFrames[0] })
        #expect(mutableFrames.count == frameCount)
        #expect(mutableFrames.first != mutableFrames.last)
        #expect(staticFrames.allSatisfy { $0.count == glyphsPerFrame })
        #expect(mutableFrames.allSatisfy { $0.count == glyphsPerFrame })

        for (scenario, frames) in [("static", staticFrames), ("mutable", mutableFrames)] {
            let command = try runCommandAtlases(frames: frames, font: font, fontSize: fontSize)
            let cpuCache = try runCPUMaskCache(frames: frames, font: font, fontSize: fontSize)
            let paged = try runPagedAtlas(
                frames: frames,
                font: font,
                fontSize: fontSize,
                pageSize: pageSize
            )
            let commandMedian = try medianFrameTime(
                repetitions: repetitions,
                frames: frames,
                font: font,
                fontSize: fontSize,
                strategy: .commandAtlas
            )
            let cpuCacheMedian = try medianFrameTime(
                repetitions: repetitions,
                frames: frames,
                font: font,
                fontSize: fontSize,
                strategy: .cpuMaskCache
            )
            let pagedMedian = try medianFrameTime(
                repetitions: repetitions,
                frames: frames,
                font: font,
                fontSize: fontSize,
                strategy: .pagedAtlas(pageSize: pageSize)
            )

            #expect(command.rasterizations == frameCount * glyphsPerFrame)
            #expect(command.atlasBuilds == frameCount)
            #expect(command.uploadCalls == frameCount)
            #expect(command.retainedCPUBytes == 0)
            #expect(command.retainedGPUBytes == 0)
            #expect(command.peakTransientGPUBytes == command.peakTransientCPUBytes)
            #expect(cpuCache.rasterizations == 2)
            #expect(cpuCache.atlasBuilds == frameCount)
            #expect(cpuCache.uploadCalls == frameCount)
            #expect(cpuCache.uploadedBytes == command.uploadedBytes)
            #expect(cpuCache.retainedCPUBytes > 0)
            #expect(cpuCache.retainedGPUBytes == 0)
            #expect(cpuCache.peakTransientGPUBytes == cpuCache.peakTransientCPUBytes)
            #expect(paged.rasterizations == 2)
            #expect(paged.atlasBuilds == 0)
            #expect(paged.uploadCalls == 1)
            #expect(paged.uploadedBytes == pageSize * pageSize)
            #expect(paged.retainedGPUBytes == pageSize * pageSize)
            #expect(paged.peakTransientGPUBytes == 0)
            #expect(paged.drawBatches == frameCount)

            let report = GlyphBenchmarkScenarioReport(
                name: scenario,
                frames: frameCount,
                glyphsPerFrame: glyphsPerFrame,
                distinctGlyphs: Set(frames.flatMap { $0 }).count,
                strategies: [
                    command.report(name: "commandAtlas", medianFramePreparationNanoseconds: commandMedian),
                    cpuCache.report(name: "cpuMaskCache", medianFramePreparationNanoseconds: cpuCacheMedian),
                    paged.report(name: "pagedAtlas", medianFramePreparationNanoseconds: pagedMedian)
                ]
            )
            let encoded = try JSONEncoder.sorted.encode(report)
            let json = try #require(String(data: encoded, encoding: .utf8))
            print("GLYPH_CACHE_BENCHMARK: \(json)")
        }
    }

    /// Loads the bundled font used to keep glyph rasterization reproducible.
    private func sampleFont() throws -> CGFont {
        let fontURL = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        return try #require(CGFont(fontURL.path))
    }

    /// Repeats one glyph sequence to create a fixed-text frame workload.
    /// - Parameters:
    ///   - text: The repeated text contents.
    ///   - count: The number of frames to produce.
    ///   - font: The font used to resolve text into glyph identifiers.
    /// - Returns: One glyph-identifier sequence per frame.
    private func makeFrames(_ text: String, count: Int, font: CGFont) throws -> [[CGGlyph]] {
        let frame = try glyphs(in: text, font: font)
        return (0..<count).map { _ in frame }
    }

    /// Resolves every character in a string through the supplied font.
    /// - Parameters:
    ///   - text: The characters to resolve.
    ///   - font: The font that maps characters to glyph identifiers.
    /// - Returns: Glyph identifiers in text order.
    private func glyphs(in text: String, font: CGFont) throws -> [CGGlyph] {
        try text.map { character in
            try #require(font.glyph(for: character))
        }
    }

    /// Measures production rasterization and packing once for each text command.
    /// - Parameters:
    ///   - frames: The glyph sequences to process.
    ///   - font: The font used for rasterization.
    ///   - fontSize: The rasterization height in pixels.
    /// - Returns: Operation counts and logical transient-memory metrics.
    private func runCommandAtlases(
        frames: [[CGGlyph]],
        font: CGFont,
        fontSize: Double
    ) throws -> GlyphBenchmarkMetrics {
        var metrics = GlyphBenchmarkMetrics()
        for frame in frames {
            let bitmaps = frame.map { font.rasterizedGlyph($0, at: fontSize) }
            let atlas = try #require(CGGlyphAtlas(bitmaps: bitmaps))
            metrics.rasterizations += frame.count
            metrics.atlasBuilds += 1
            metrics.uploadCalls += 1
            metrics.uploadedBytes += atlas.coverage.count
            metrics.peakTransientCPUBytes = max(metrics.peakTransientCPUBytes, atlas.coverage.count)
            metrics.peakTransientGPUBytes = max(metrics.peakTransientGPUBytes, atlas.coverage.count)
            metrics.drawBatches += 1
        }
        return metrics
    }

    /// Measures cached source masks while rebuilding and uploading command atlases.
    /// - Parameters:
    ///   - frames: The glyph sequences to process.
    ///   - font: The font used for cache misses.
    ///   - fontSize: The rasterization height in pixels.
    /// - Returns: Operation counts and logical retained/transient-memory metrics.
    private func runCPUMaskCache(
        frames: [[CGGlyph]],
        font: CGFont,
        fontSize: Double
    ) throws -> GlyphBenchmarkMetrics {
        var metrics = GlyphBenchmarkMetrics()
        var masks: [CGGlyph: CGGlyphBitmap] = [:]
        for frame in frames {
            var bitmaps: [CGGlyphBitmap?] = []
            bitmaps.reserveCapacity(frame.count)
            for glyph in frame {
                if let bitmap = masks[glyph] {
                    bitmaps.append(bitmap)
                } else {
                    let bitmap = try #require(font.rasterizedGlyph(glyph, at: fontSize))
                    masks[glyph] = bitmap
                    metrics.rasterizations += 1
                    bitmaps.append(bitmap)
                }
            }
            let atlas = try #require(CGGlyphAtlas(bitmaps: bitmaps))
            metrics.atlasBuilds += 1
            metrics.uploadCalls += 1
            metrics.uploadedBytes += atlas.coverage.count
            metrics.peakTransientCPUBytes = max(metrics.peakTransientCPUBytes, atlas.coverage.count)
            metrics.peakTransientGPUBytes = max(metrics.peakTransientGPUBytes, atlas.coverage.count)
            metrics.drawBatches += 1
        }
        metrics.retainedCPUBytes = masks.values.reduce(0) { $0 + $1.coverage.count }
        return metrics
    }

    /// Measures the bounded-page prototype using persistent R8 page storage.
    /// - Parameters:
    ///   - frames: The glyph sequences to process.
    ///   - font: The font used for cache misses.
    ///   - fontSize: The rasterization height in pixels.
    ///   - pageSize: The square page dimension used by the prototype.
    /// - Returns: Operation counts and logical retained-memory metrics.
    private func runPagedAtlas(
        frames: [[CGGlyph]],
        font: CGFont,
        fontSize: Double,
        pageSize: Int
    ) throws -> GlyphBenchmarkMetrics {
        var metrics = GlyphBenchmarkMetrics()
        var cache = GlyphPagePrototype(pageSize: pageSize)
        for frame in frames {
            let missingGlyphs = Set(frame).subtracting(cache.placements.keys).sorted()
            var pendingUploads: [(page: Int, bytes: Int)] = []
            for glyph in missingGlyphs {
                let bitmap = try #require(font.rasterizedGlyph(glyph, at: fontSize))
                metrics.rasterizations += 1
                let optionalInsertion = cache.insert(bitmap, for: glyph)
                let insertion = try #require(optionalInsertion)
                if insertion.createdPage {
                    pendingUploads.append((insertion.page, pageSize * pageSize))
                } else {
                    pendingUploads.append((insertion.page, bitmap.coverage.count))
                }
            }

            let newPages = Set(pendingUploads.filter { $0.bytes == pageSize * pageSize }.map(\.page))
            for _ in newPages {
                metrics.uploadCalls += 1
                metrics.uploadedBytes += pageSize * pageSize
            }
            for upload in pendingUploads where newPages.contains(upload.page) == false {
                metrics.uploadCalls += 1
                metrics.uploadedBytes += upload.bytes
            }
            metrics.drawBatches += Set(frame.compactMap { cache.placements[$0] }).count
        }
        metrics.retainedCPUBytes = cache.cpuByteCount
        metrics.retainedGPUBytes = cache.pageCount * pageSize * pageSize
        return metrics
    }

    /// Returns the median per-frame preparation duration after a warm-up pass.
    /// - Parameters:
    ///   - repetitions: The number of measured full-workload passes.
    ///   - frames: The glyph sequences to process.
    ///   - font: The font used by the selected strategy.
    ///   - fontSize: The rasterization height in pixels.
    ///   - strategy: The workload preparation strategy.
    /// - Returns: Median preparation nanoseconds per frame.
    private func medianFrameTime(
        repetitions: Int,
        frames: [[CGGlyph]],
        font: CGFont,
        fontSize: Double,
        strategy: GlyphBenchmarkStrategy
    ) throws -> Double {
        _ = try run(strategy, frames: frames, font: font, fontSize: fontSize)
        var samples: [Double] = []
        for _ in 0..<repetitions {
            let clock = ContinuousClock()
            let start = clock.now
            _ = try run(strategy, frames: frames, font: font, fontSize: fontSize)
            let elapsed = nanoseconds(in: start.duration(to: clock.now))
            samples.append(elapsed / Double(frames.count))
        }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Runs one complete workload using the selected preparation strategy.
    /// - Parameters:
    ///   - strategy: The workload preparation strategy.
    ///   - frames: The glyph sequences to process.
    ///   - font: The font used by the selected strategy.
    ///   - fontSize: The rasterization height in pixels.
    /// - Returns: The operation counts and logical memory metrics.
    private func run(
        _ strategy: GlyphBenchmarkStrategy,
        frames: [[CGGlyph]],
        font: CGFont,
        fontSize: Double
    ) throws -> GlyphBenchmarkMetrics {
        switch strategy {
        case .commandAtlas:
            try runCommandAtlases(frames: frames, font: font, fontSize: fontSize)
        case .cpuMaskCache:
            try runCPUMaskCache(frames: frames, font: font, fontSize: fontSize)
        case let .pagedAtlas(pageSize):
            try runPagedAtlas(frames: frames, font: font, fontSize: fontSize, pageSize: pageSize)
        }
    }

    /// Converts a monotonic duration to nanoseconds.
    /// - Parameter duration: The measured duration.
    /// - Returns: The equivalent duration in nanoseconds.
    private func nanoseconds(in duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
    }
}

/// The test-only approaches compared by the glyph workload.
private enum GlyphBenchmarkStrategy {
    /// Builds and uploads an atlas for every text command.
    case commandAtlas
    /// Caches individual CPU masks but rebuilds each command atlas.
    case cpuMaskCache
    /// Keeps masks in persistent square atlas pages.
    case pagedAtlas(pageSize: Int)
}

/// Counters and logical memory measurements from one strategy pass.
private struct GlyphBenchmarkMetrics: Encodable {
    /// Rasterization calls made during the workload.
    var rasterizations = 0
    /// Number of production per-command atlases built.
    var atlasBuilds = 0
    /// Modeled texture creation or subregion-update operations.
    var uploadCalls = 0
    /// Modeled R8 bytes submitted to the texture loader.
    var uploadedBytes = 0
    /// Logical CPU bytes retained by the strategy after the workload.
    var retainedCPUBytes = 0
    /// Logical GPU bytes retained by the strategy after the workload.
    var retainedGPUBytes = 0
    /// Largest one-frame CPU atlas allocation.
    var peakTransientCPUBytes = 0
    /// Largest one-frame GPU atlas allocation.
    var peakTransientGPUBytes = 0
    /// Draw batches counted for the workload.
    var drawBatches = 0

    /// Creates a report row with the measured median frame-preparation duration.
    /// - Parameters:
    ///   - name: The strategy name.
    ///   - medianFramePreparationNanoseconds: Median CPU preparation time per frame.
    /// - Returns: A serializable report row.
    func report(name: String, medianFramePreparationNanoseconds: Double) -> GlyphBenchmarkStrategyReport {
        GlyphBenchmarkStrategyReport(
            name: name,
            rasterizations: rasterizations,
            atlasBuilds: atlasBuilds,
            uploadCalls: uploadCalls,
            uploadedBytes: uploadedBytes,
            retainedCPUBytes: retainedCPUBytes,
            retainedGPUBytes: retainedGPUBytes,
            peakTransientCPUBytes: peakTransientCPUBytes,
            peakTransientGPUBytes: peakTransientGPUBytes,
            drawBatches: drawBatches,
            medianFramePreparationNanoseconds: medianFramePreparationNanoseconds
        )
    }
}

/// Scenario-level workload details and strategy results.
private struct GlyphBenchmarkScenarioReport: Encodable {
    /// Scenario name, either static or mutable.
    let name: String
    /// Number of frames in the workload.
    let frames: Int
    /// Glyph occurrences submitted in each frame.
    let glyphsPerFrame: Int
    /// Number of distinct glyph identifiers used across the scenario.
    let distinctGlyphs: Int
    /// Measured counters for each strategy.
    let strategies: [GlyphBenchmarkStrategyReport]
}

/// Serializable metrics for one strategy and workload scenario.
private struct GlyphBenchmarkStrategyReport: Encodable {
    /// Strategy name.
    let name: String
    /// Number of glyph rasterizations.
    let rasterizations: Int
    /// Number of per-command atlas builds.
    let atlasBuilds: Int
    /// Number of modeled texture upload operations.
    let uploadCalls: Int
    /// Number of modeled bytes uploaded.
    let uploadedBytes: Int
    /// Logical CPU bytes retained after the workload.
    let retainedCPUBytes: Int
    /// Logical GPU bytes retained after the workload.
    let retainedGPUBytes: Int
    /// Peak one-frame CPU atlas allocation.
    let peakTransientCPUBytes: Int
    /// Peak one-frame GPU atlas allocation.
    let peakTransientGPUBytes: Int
    /// Number of draw batches counted.
    let drawBatches: Int
    /// Median CPU preparation time per frame in nanoseconds.
    let medianFramePreparationNanoseconds: Double
}

/// A test-only shelf-packed atlas that models persistent fixed-size R8 pages.
private struct GlyphPagePrototype {
    /// Pixel storage and shelf-packing cursor for one page.
    private struct Page {
        /// Full page coverage bytes in row-major order.
        var coverage: [UInt8]
        /// Horizontal position for the next glyph.
        var cursorX = 1
        /// Vertical position for the current shelf.
        var cursorY = 1
        /// Maximum glyph height in the current shelf.
        var rowHeight = 0
    }

    /// Width and height of each square page.
    let pageSize: Int
    /// Persistent test-prototype pages.
    private var pages: [Page] = []
    /// Page index assigned to every cached glyph.
    private(set) var placements: [CGGlyph: Int] = [:]
    /// Source masks retained by the prototype.
    private var masks: [CGGlyph: CGGlyphBitmap] = [:]

    /// CPU bytes held by page storage and retained source masks.
    var cpuByteCount: Int {
        pages.reduce(0) { $0 + $1.coverage.count }
            + masks.values.reduce(0) { $0 + $1.coverage.count }
    }

    /// Number of allocated fixed-size pages.
    var pageCount: Int {
        pages.count
    }

    /// Packs a mask into a page, allocating another page when needed.
    /// - Parameters:
    ///   - bitmap: The glyph coverage mask to pack.
    ///   - glyph: The identifier associated with the mask.
    /// - Returns: Its page and whether this operation allocated that page.
    mutating func insert(_ bitmap: CGGlyphBitmap, for glyph: CGGlyph) -> (page: Int, createdPage: Bool)? {
        guard bitmap.width > 0, bitmap.height > 0,
              bitmap.width + 2 <= pageSize, bitmap.height + 2 <= pageSize else {
            return nil
        }
        var createdPage = false
        if pages.isEmpty {
            pages.append(Page(coverage: [UInt8](repeating: 0, count: pageSize * pageSize)))
            createdPage = true
        }
        if canFit(bitmap, in: pages[pages.count - 1]) == false {
            pages.append(Page(coverage: [UInt8](repeating: 0, count: pageSize * pageSize)))
            createdPage = true
        }
        let pageIndex = pages.count - 1
        pack(bitmap, into: &pages[pageIndex])
        placements[glyph] = pageIndex
        masks[glyph] = bitmap
        return (pageIndex, createdPage)
    }

    /// Determines whether the current page can fit a glyph on its current or next shelf.
    /// - Parameters:
    ///   - bitmap: The glyph coverage mask to fit.
    ///   - page: The candidate atlas page.
    /// - Returns: Whether the mask fits within the page bounds.
    private func canFit(_ bitmap: CGGlyphBitmap, in page: Page) -> Bool {
        let currentWidth = page.cursorX + bitmap.width + 1
        if currentWidth <= pageSize, page.cursorY + bitmap.height + 1 <= pageSize {
            return true
        }
        return page.cursorY + page.rowHeight + bitmap.height + 2 <= pageSize
            && bitmap.width + 2 <= pageSize
    }

    /// Copies the glyph coverage into the page and advances its shelf cursor.
    /// - Parameters:
    ///   - bitmap: The glyph coverage mask to copy.
    ///   - page: The page being modified.
    private func pack(_ bitmap: CGGlyphBitmap, into page: inout Page) {
        if page.cursorX + bitmap.width + 1 > pageSize {
            page.cursorX = 1
            page.cursorY += page.rowHeight + 2
            page.rowHeight = 0
        }
        for row in 0..<bitmap.height {
            let sourceStart = row * bitmap.width
            let destinationStart = (page.cursorY + row) * pageSize + page.cursorX
            for column in 0..<bitmap.width {
                page.coverage[destinationStart + column] = bitmap.coverage[sourceStart + column]
            }
        }
        page.cursorX += bitmap.width + 2
        page.rowHeight = max(page.rowHeight, bitmap.height)
    }
}

/// Creates a JSON encoder with stable key ordering for benchmark output.
private extension JSONEncoder {
    /// Encoder configured for deterministic key ordering.
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
