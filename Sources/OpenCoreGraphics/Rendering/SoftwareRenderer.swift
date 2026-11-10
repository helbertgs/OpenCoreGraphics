import Foundation

/// Renders paths into a bitmap surface without GPU dependencies.
final class SoftwareRenderer: CGRenderBackend {
    /// The bitmap that receives rendered pixels.
    private let surface: PixelSurface

    /// The optional coverage mask applied to subsequent drawing.
    private var clipMask: CoverageMask?

    /// Creates a renderer for the supplied pixel storage.
    /// - Parameter surface: The bitmap that receives rendered output.
    init(surface: PixelSurface) {
        self.surface = surface
    }

    /// Executes fill and stroke commands in submission order.
    /// - Parameters:
    ///   - commands: The operations to render.
    ///   - size: The bitmap dimensions in pixels.
    func execute(_ commands: [DrawCommand], size: CGSize) {
        for command in commands {
            switch command {
            case let .fillPath(path, rule, color, blendMode):
                if let rectangle = alignedRectangle(in: path) {
                    fill(rectangle, color: color, blendMode: blendMode)
                } else {
                    fill(PathFlattener.flatten(path), rule: rule, color: color, blendMode: blendMode)
                }
            case let .strokePath(path, color, style, blendMode):
                let outlines = Stroker.outline(PathFlattener.flatten(path), style: style)
                fill(outlines, rule: .winding, color: color, blendMode: blendMode)
            case .drawImage, .clip, .glyphs:
                continue
            }
        }
    }

    /// Returns a snapshot of the rendered bitmap bytes.
    /// - Returns: A copy of all pixel rows, including row padding.
    func readPixels() -> Data {
        Data(bytes: surface.dataPointer, count: surface.byteCount)
    }

    /// Replaces the coverage mask applied to subsequent drawing.
    /// - Parameter mask: The current clip coverage, or nil to remove clipping.
    func setClipMask(_ mask: CoverageMask?) {
        clipMask = mask
    }

    /// Fills an aligned rectangle using clear or premultiplied source-over composition.
    /// - Parameters:
    ///   - rectangle: The pixel-aligned rectangle to fill.
    ///   - color: The source color.
    ///   - blendMode: The compositing operation.
    private func fill(_ rectangle: CGRect, color: CGColor, blendMode: CGBlendMode) {
        let minimumX = max(0, min(Double(surface.width), rectangle.minX))
        let minimumY = max(0, min(Double(surface.height), rectangle.minY))
        let maximumX = max(0, min(Double(surface.width), rectangle.maxX))
        let maximumY = max(0, min(Double(surface.height), rectangle.maxY))
        let firstX = Int(minimumX)
        let firstY = Int(minimumY)
        let lastX = Int(maximumX)
        let lastY = Int(maximumY)

        guard firstX < lastX, firstY < lastY else { return }
        if blendMode == .clear {
            for y in firstY..<lastY {
                for x in firstX..<lastX {
                    let coverage = Double(clippingCoverage(atX: x, y: y)) / 255
                    guard coverage > 0 else { continue }
                    clear(x: x, y: y, coverage: coverage)
                }
            }
            return
        }
        guard blendMode == .normal,
              let source = rgbaComponents(for: color) else {
            return
        }

        for y in firstY..<lastY {
            for x in firstX..<lastX {
                let coverage = Double(clippingCoverage(atX: x, y: y)) / 255
                guard coverage > 0 else { continue }
                composite(source, coverage: coverage, x: x, y: y)
            }
        }
    }

    /// Rasterizes a flattened path and composites its antialiased coverage.
    /// - Parameters:
    ///   - path: The path whose interior is rendered.
    ///   - rule: The fill rule used to determine interior regions.
    ///   - color: The source color.
    ///   - blendMode: The compositing operation.
    private func fill(_ polylines: [Polyline], rule: CGPath.CGPathFillRule, color: CGColor, blendMode: CGBlendMode) {
        guard let coverage = ScanlineRasterizer.coverage(
            for: polylines,
            rule: rule,
            width: surface.width,
            height: surface.height
        ) else {
            return
        }

        if blendMode == .clear {
            for y in 0..<surface.height {
                for x in 0..<surface.width {
                    let value = coverage[y * surface.width + x]
                    let clipCoverage = clippingCoverage(atX: x, y: y)
                    let combinedCoverage = (Int(value) * Int(clipCoverage) + 127) / 255
                    guard combinedCoverage > 0 else { continue }
                    clear(x: x, y: y, coverage: Double(combinedCoverage) / 255)
                }
            }
            return
        }
        guard blendMode == .normal,
              let source = rgbaComponents(for: color) else {
            return
        }

        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let value = coverage[y * surface.width + x]
                let clipCoverage = clippingCoverage(atX: x, y: y)
                let combinedCoverage = (Int(value) * Int(clipCoverage) + 127) / 255
                guard combinedCoverage > 0 else { continue }
                composite(source, coverage: Double(combinedCoverage) / 255, x: x, y: y)
            }
        }
    }

    /// Returns full coverage without a clip and zero outside an active mask.
    /// - Parameters:
    ///   - x: The destination pixel column.
    ///   - y: The destination pixel row.
    /// - Returns: The coverage byte that limits this destination pixel.
    private func clippingCoverage(atX x: Int, y: Int) -> UInt8 {
        guard let clipMask else { return 255 }
        return clipMask.coverage(atX: x, y: y) ?? 0
    }

    /// Applies source-over composition using a premultiplied color and coverage.
    /// - Parameters:
    ///   - source: The normalized, unpremultiplied RGBA source components.
    ///   - coverage: The fraction of the destination pixel covered by the path.
    ///   - x: The destination pixel column.
    ///   - y: The destination pixel row.
    private func composite(_ source: [Double], coverage: Double, x: Int, y: Int) {
        guard let destination = surface.pixel(x: x, y: y) else { return }
        let sourceAlpha = source[3] * coverage
        let remainingAlpha = 1 - sourceAlpha
        let destinationAlpha = Double(destination.alpha) / 255
        let output = PixelSurface.Pixel(
            red: channel(source[0] * sourceAlpha + Double(destination.red) / 255 * remainingAlpha),
            green: channel(source[1] * sourceAlpha + Double(destination.green) / 255 * remainingAlpha),
            blue: channel(source[2] * sourceAlpha + Double(destination.blue) / 255 * remainingAlpha),
            alpha: channel(sourceAlpha + destinationAlpha * remainingAlpha)
        )
        surface.setPixel(output, x: x, y: y)
    }

    /// Clears a covered portion of a destination pixel.
    /// - Parameters:
    ///   - x: The destination pixel column.
    ///   - y: The destination pixel row.
    ///   - coverage: The fraction of the destination pixel cleared.
    private func clear(x: Int, y: Int, coverage: Double) {
        guard let destination = surface.pixel(x: x, y: y) else { return }
        let remaining = 1 - coverage
        surface.setPixel(
            PixelSurface.Pixel(
                red: channel(Double(destination.red) / 255 * remaining),
                green: channel(Double(destination.green) / 255 * remaining),
                blue: channel(Double(destination.blue) / 255 * remaining),
                alpha: channel(Double(destination.alpha) / 255 * remaining)
            ),
            x: x,
            y: y
        )
    }

    /// Finds a single closed axis-aligned rectangle whose vertices lie on pixel boundaries.
    /// - Parameter path: The path to inspect.
    /// - Returns: Its rectangle when the path has exactly four aligned corners.
    private func alignedRectangle(in path: CGPath) -> CGRect? {
        let polylines = PathFlattener.flatten(path)
        guard polylines.count == 1,
              let polyline = polylines.first,
              polyline.isClosed,
              polyline.points.count == 4,
              polyline.points.allSatisfy({
                  $0.x.isFinite && $0.y.isFinite && $0.x.rounded() == $0.x && $0.y.rounded() == $0.y
              }) else {
            return nil
        }

        let minimumX = polyline.points.map(\.x).min() ?? 0
        let minimumY = polyline.points.map(\.y).min() ?? 0
        let maximumX = polyline.points.map(\.x).max() ?? 0
        let maximumY = polyline.points.map(\.y).max() ?? 0
        guard minimumX < maximumX, minimumY < maximumY else { return nil }
        let corners = [
            CGPoint(x: minimumX, y: minimumY),
            CGPoint(x: maximumX, y: minimumY),
            CGPoint(x: maximumX, y: maximumY),
            CGPoint(x: minimumX, y: maximumY)
        ]
        guard corners.allSatisfy({ corner in polyline.points.contains(corner) }) else { return nil }
        return CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
    }

    /// Converts supported color spaces to normalized, unpremultiplied RGBA components.
    /// - Parameter color: The source color.
    /// - Returns: Four finite components clamped to the unit range, or nil when unsupported.
    private func rgbaComponents(for color: CGColor) -> [Double]? {
        guard let colorSpace = color.colorSpace else { return nil }
        let components: [Double]
        switch colorSpace.model {
        case .rgb:
            guard color.components.count == 4 else { return nil }
            components = color.components
        case .gray:
            guard color.components.count == 2 else { return nil }
            components = [color.components[0], color.components[0], color.components[0], color.components[1]]
        case .cmyk:
            guard color.components.count == 5 else { return nil }
            let black = color.components[3]
            components = [
                (1 - color.components[0]) * (1 - black),
                (1 - color.components[1]) * (1 - black),
                (1 - color.components[2]) * (1 - black),
                color.components[4]
            ]
        case .deviceN, .lab:
            return nil
        }
        guard components.allSatisfy(\.isFinite) else { return nil }
        return components.map { min(1, max(0, $0)) }
    }

    /// Converts a normalized component to its nearest 8-bit channel value.
    /// - Parameter value: A component in the unit range.
    /// - Returns: The rounded channel byte.
    private func channel(_ value: Double) -> UInt8 {
        UInt8((min(1, max(0, value)) * 255).rounded())
    }
}

/// Rasterizes flattened contours with a fixed 4×4 sample grid per pixel.
fileprivate enum ScanlineRasterizer {
    /// The number of subpixel samples taken along each pixel axis.
    private static let samplesPerAxis = 4

    /// A scanline intersection with its signed winding contribution.
    private struct Crossing {
        /// The horizontal coordinate of this intersection.
        let x: Double

        /// The winding change contributed by crossing this contour edge.
        let direction: Int
    }

    /// Produces one 8-bit coverage value for each pixel using scanline intersections.
    /// - Parameters:
    ///   - polylines: The flattened contours to fill.
    ///   - rule: The fill rule used to determine interior regions.
    ///   - width: The destination width in pixels.
    ///   - height: The destination height in pixels.
    /// - Returns: Row-major coverage bytes, or nil when the destination size is invalid.
    fileprivate static func coverage(
        for polylines: [Polyline],
        rule: CGPath.CGPathFillRule,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, overflow == false else { return nil }
        var sampleCoverage = [UInt8](repeating: 0, count: pixelCount)
        let sampleOffsets = (0..<samplesPerAxis).map { (Double($0) + 0.5) / Double(samplesPerAxis) }

        for pixelY in 0..<height {
            for yOffset in sampleOffsets {
                let scanY = Double(pixelY) + yOffset
                let crossings = intersections(on: scanY, in: polylines)
                var crossingIndex = 0
                var windingNumber = 0
                var isInsideEvenOdd = false

                for pixelX in 0..<width {
                    for xOffset in sampleOffsets {
                        let sampleX = Double(pixelX) + xOffset
                        while crossingIndex < crossings.count, crossings[crossingIndex].x <= sampleX {
                            windingNumber += crossings[crossingIndex].direction
                            isInsideEvenOdd.toggle()
                            crossingIndex += 1
                        }

                        let isInside = rule == .evenOdd ? isInsideEvenOdd : windingNumber != 0
                        if isInside {
                            sampleCoverage[pixelY * width + pixelX] += 1
                        }
                    }

                }
            }
        }

        let sampleCount = samplesPerAxis * samplesPerAxis
        return sampleCoverage.map { UInt8((Int($0) * 255 + sampleCount / 2) / sampleCount) }
    }

    /// Finds all edge intersections with one horizontal sample line.
    /// - Parameters:
    ///   - scanY: The vertical coordinate of the sample line.
    ///   - polylines: The flattened path contours.
    /// - Returns: Sorted intersections with parity or signed winding contributions.
    private static func intersections(on scanY: Double, in polylines: [Polyline]) -> [Crossing] {
        var crossings: [Crossing] = []
        for polyline in polylines where polyline.points.count > 1 {
            for index in polyline.points.indices {
                let start = polyline.points[index]
                let end = polyline.points[(index + 1) % polyline.points.count]
                guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { continue }

                let direction: Int
                if start.y <= scanY, end.y > scanY {
                    direction = 1
                } else if end.y <= scanY, start.y > scanY {
                    direction = -1
                } else {
                    continue
                }

                let fraction = (scanY - start.y) / (end.y - start.y)
                let intersectionX = start.x + fraction * (end.x - start.x)
                guard intersectionX.isFinite else { continue }
                crossings.append(Crossing(x: intersectionX, direction: direction))
            }
        }

        crossings.sort { $0.x < $1.x }
        return crossings
    }
}

/// Stores per-pixel coverage for the current clipping region.
struct CoverageMask: Equatable, Sendable {
    /// The width of the covered bitmap in pixels.
    let width: Int

    /// The height of the covered bitmap in pixels.
    let height: Int

    /// Row-major coverage values with one byte per pixel.
    private let values: [UInt8]

    /// Creates a coverage mask by rasterizing a path with the selected fill rule.
    /// - Parameters:
    ///   - path: The path defining the clipping region.
    ///   - rule: The fill rule used to determine interior regions.
    ///   - width: The clipping surface width in pixels.
    ///   - height: The clipping surface height in pixels.
    /// - Returns: A mask when its dimensions are valid.
    init?(path: CGPath, rule: CGPath.CGPathFillRule, width: Int, height: Int) {
        guard let values = ScanlineRasterizer.coverage(
            for: PathFlattener.flatten(path),
            rule: rule,
            width: width,
            height: height
        ) else {
            return nil
        }
        self.width = width
        self.height = height
        self.values = values
    }

    /// Intersects this mask with another mask of matching dimensions.
    /// - Parameter other: The additional clipping coverage to intersect.
    /// - Returns: The combined mask, or nil if the dimensions differ.
    func intersecting(_ other: CoverageMask) -> CoverageMask? {
        guard width == other.width, height == other.height else { return nil }
        let combinedValues = zip(values, other.values).map {
            UInt8((Int($0) * Int($1) + 127) / 255)
        }
        return CoverageMask(width: width, height: height, values: combinedValues)
    }

    /// Returns coverage at a pixel coordinate.
    /// - Parameters:
    ///   - x: The pixel column.
    ///   - y: The pixel row.
    /// - Returns: The coverage byte, or nil when the coordinate is outside the mask.
    fileprivate func coverage(atX x: Int, y: Int) -> UInt8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return values[y * width + x]
    }

    /// Creates a mask from already-combined coverage bytes.
    /// - Parameters:
    ///   - width: The clipping surface width in pixels.
    ///   - height: The clipping surface height in pixels.
    ///   - values: Row-major per-pixel coverage values.
    private init(width: Int, height: Int, values: [UInt8]) {
        self.width = width
        self.height = height
        self.values = values
    }
}
