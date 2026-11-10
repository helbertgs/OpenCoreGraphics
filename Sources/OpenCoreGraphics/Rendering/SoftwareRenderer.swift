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
            case let .fillPath(path, rule, color, blendMode, shadow):
                if let rectangle = alignedRectangle(in: path) {
                    fill(rectangle, color: color, blendMode: blendMode, shadow: shadow)
                } else {
                    fill(
                        PathFlattener.flatten(path),
                        rule: rule,
                        color: color,
                        blendMode: blendMode,
                        shadow: shadow
                    )
                }
            case let .strokePath(path, color, style, blendMode, shadow):
                let outlines = Stroker.outline(PathFlattener.flatten(path), style: style)
                fill(outlines, rule: .winding, color: color, blendMode: blendMode, shadow: shadow)
            case let .linearGradient(gradient, start, end, options, blendMode):
                drawLinearGradient(
                    gradient,
                    start: start,
                    end: end,
                    options: options,
                    blendMode: blendMode
                )
            case let .radialGradient(gradient, startCenter, startRadius, endCenter, endRadius, options, blendMode):
                drawRadialGradient(
                    gradient,
                    startCenter: startCenter,
                    startRadius: startRadius,
                    endCenter: endCenter,
                    endRadius: endRadius,
                    options: options,
                    blendMode: blendMode
                )
            case let .drawImage(image, destination, interpolationQuality, byTiling, blendMode):
                drawImage(
                    image,
                    destination: destination,
                    interpolationQuality: interpolationQuality,
                    byTiling: byTiling,
                    blendMode: blendMode
                )
            case let .glyphs(
                glyphs,
                positions,
                _,
                _,
                glyphBitmaps,
                characterSpacing,
                textMatrix,
                textPosition,
                ctm,
                color,
                blendMode
            ):
                drawGlyphs(
                    glyphs,
                    positions: positions,
                    glyphBitmaps: glyphBitmaps,
                    characterSpacing: characterSpacing,
                    textMatrix: textMatrix,
                    textPosition: textPosition,
                    ctm: ctm,
                    color: color,
                    blendMode: blendMode
                )
            case .clip, .clipRect, .resetClip:
                continue
            }
        }
    }

    /// Interpolates linear-gradient colors at each pixel center.
    /// - Parameters:
    ///   - gradient: The ordered color stops to render.
    ///   - start: The gradient's device-space start point.
    ///   - end: The gradient's device-space end point.
    ///   - options: The behavior outside the first and last stops.
    ///   - blendMode: The compositing operation for the gradient.
    private func drawLinearGradient(
        _ gradient: CGGradient,
        start: CGPoint,
        end: CGPoint,
        options: CGGradientDrawingOptions,
        blendMode: CGBlendMode
    ) {
        guard let colors = linearGradientColors(gradient) else { return }
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY

        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let pointX = Double(x) + 0.5
                let pointY = Double(y) + 0.5
                let position = lengthSquared > 0
                    ? ((pointX - start.x) * deltaX + (pointY - start.y) * deltaY) / lengthSquared
                    : 0
                guard let source = gradientColor(
                    at: position,
                    gradient: gradient,
                    colors: colors,
                    options: options
                ) else {
                    continue
                }
                compositeGradientPixel(source, x: x, y: y, blendMode: blendMode)
            }
        }
    }

    /// Interpolates radial-gradient colors using the circles' device-space geometry.
    /// - Parameters:
    ///   - gradient: The ordered color stops to render.
    ///   - startCenter: The first circle's device-space center.
    ///   - startRadius: The first circle's device-space radius.
    ///   - endCenter: The last circle's device-space center.
    ///   - endRadius: The last circle's device-space radius.
    ///   - options: The behavior outside the first and last stops.
    ///   - blendMode: The compositing operation for the gradient.
    private func drawRadialGradient(
        _ gradient: CGGradient,
        startCenter: CGPoint,
        startRadius: Double,
        endCenter: CGPoint,
        endRadius: Double,
        options: CGGradientDrawingOptions,
        blendMode: CGBlendMode
    ) {
        guard let colors = linearGradientColors(gradient) else { return }
        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                guard let position = radialGradientPosition(
                    at: point,
                    startCenter: startCenter,
                    startRadius: startRadius,
                    endCenter: endCenter,
                    endRadius: endRadius
                ), let source = gradientColor(
                    at: position,
                    gradient: gradient,
                    colors: colors,
                    options: options
                ) else {
                    continue
                }
                compositeGradientPixel(source, x: x, y: y, blendMode: blendMode)
            }
        }
    }

    /// Converts each gradient stop to premultiplied linear RGBA.
    /// - Parameter gradient: The gradient whose stops should be converted.
    /// - Returns: The converted stops, or nil if any color is unsupported.
    private func linearGradientColors(_ gradient: CGGradient) -> [[Double]]? {
        let colors = gradient.colors.compactMap(rgbaComponents(for:))
        return colors.count == gradient.colors.count ? colors : nil
    }

    /// Interpolates premultiplied stop colors at one normalized gradient position.
    /// - Parameters:
    ///   - position: The gradient parameter for a pixel.
    ///   - gradient: The ordered gradient stops.
    ///   - colors: Their premultiplied linear RGBA values.
    ///   - options: The behavior outside the first and last stops.
    /// - Returns: The interpolated color, or nil for an unextended out-of-range position.
    private func gradientColor(
        at position: Double,
        gradient: CGGradient,
        colors: [[Double]],
        options: CGGradientDrawingOptions
    ) -> [Double]? {
        guard position.isFinite,
              let firstLocation = gradient.locations.first,
              let lastLocation = gradient.locations.last,
              let firstColor = colors.first,
              let lastColor = colors.last else {
            return nil
        }
        if position < firstLocation {
            return options.contains(.drawsBeforeStartLocation) ? firstColor : nil
        }
        if position > lastLocation {
            return options.contains(.drawsAfterEndLocation) ? lastColor : nil
        }

        guard let upperIndex = gradient.locations.firstIndex(where: { $0 >= position }) else {
            return lastColor
        }
        if upperIndex == 0 { return firstColor }
        let lowerIndex = upperIndex - 1
        let lowerLocation = gradient.locations[lowerIndex]
        let upperLocation = gradient.locations[upperIndex]
        let fraction = upperLocation == lowerLocation
            ? 1
            : (position - lowerLocation) / (upperLocation - lowerLocation)
        return (0..<4).map { component in
            colors[lowerIndex][component] * (1 - fraction) + colors[upperIndex][component] * fraction
        }
    }

    /// Solves for the parameter of the circle that passes through a point.
    /// - Parameters:
    ///   - point: The device-space pixel center.
    ///   - startCenter: The first circle's center.
    ///   - startRadius: The first circle's radius.
    ///   - endCenter: The last circle's center.
    ///   - endRadius: The last circle's radius.
    /// - Returns: The largest finite real solution, or nil when no circle passes through the point.
    private func radialGradientPosition(
        at point: CGPoint,
        startCenter: CGPoint,
        startRadius: Double,
        endCenter: CGPoint,
        endRadius: Double
    ) -> Double? {
        let deltaX = endCenter.x - startCenter.x
        let deltaY = endCenter.y - startCenter.y
        let radiusDelta = endRadius - startRadius
        let pointX = point.x - startCenter.x
        let pointY = point.y - startCenter.y
        let a = deltaX * deltaX + deltaY * deltaY - radiusDelta * radiusDelta
        let b = -2 * (pointX * deltaX + pointY * deltaY + startRadius * radiusDelta)
        let c = pointX * pointX + pointY * pointY - startRadius * startRadius

        if abs(a) <= Double.ulpOfOne {
            guard b != 0 else { return c == 0 ? 0 : nil }
            let position = -c / b
            return position.isFinite ? position : nil
        }

        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0, discriminant.isFinite else { return nil }
        let root = sqrt(discriminant)
        let first = (-b - root) / (2 * a)
        let second = (-b + root) / (2 * a)
        let position = max(first, second)
        return position.isFinite ? position : nil
    }

    /// Composites one gradient pixel through the current clip mask.
    /// - Parameters:
    ///   - source: Premultiplied linear RGBA components.
    ///   - x: The destination pixel column.
    ///   - y: The destination pixel row.
    ///   - blendMode: The compositing operation for the pixel.
    private func compositeGradientPixel(_ source: [Double], x: Int, y: Int, blendMode: CGBlendMode) {
        let clipCoverage = Double(clippingCoverage(atX: x, y: y)) / 255
        guard clipCoverage > 0 else { return }
        composite(source, coverage: clipCoverage, blendMode: blendMode, x: x, y: y)
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

    /// Fills an aligned rectangle using the selected compositing operation.
    /// - Parameters:
    ///   - rectangle: The pixel-aligned rectangle to fill.
    ///   - color: The source color.
    ///   - blendMode: The compositing operation.
    private func fill(_ rectangle: CGRect, color: CGColor, blendMode: CGBlendMode, shadow: CGShadow?) {
        let minimumX = max(0, min(Double(surface.width), rectangle.minX))
        let minimumY = max(0, min(Double(surface.height), rectangle.minY))
        let maximumX = max(0, min(Double(surface.width), rectangle.maxX))
        let maximumY = max(0, min(Double(surface.height), rectangle.maxY))
        let firstX = Int(minimumX)
        let firstY = Int(minimumY)
        let lastX = Int(maximumX)
        let lastY = Int(maximumY)

        guard firstX < lastX, firstY < lastY else { return }
        if let shadow, blendMode != .clear {
            var coverage = [UInt8](repeating: 0, count: surface.width * surface.height)
            for y in firstY..<lastY {
                for x in firstX..<lastX {
                    coverage[y * surface.width + x] = 255
                }
            }
            renderShadow(coverage, shadow: shadow, blendMode: blendMode)
        }

        let source: [Double]
        if blendMode == .clear {
            source = [0, 0, 0, 0]
        } else {
            guard let components = rgbaComponents(for: color) else { return }
            source = components
        }

        for y in firstY..<lastY {
            for x in firstX..<lastX {
                let coverage = Double(clippingCoverage(atX: x, y: y)) / 255
                guard coverage > 0 else { continue }
                composite(source, coverage: coverage, blendMode: blendMode, x: x, y: y)
            }
        }
    }

    /// Rasterizes a flattened path and composites its antialiased coverage.
    /// - Parameters:
    ///   - path: The path whose interior is rendered.
    ///   - rule: The fill rule used to determine interior regions.
    ///   - color: The source color.
    ///   - blendMode: The compositing operation.
    private func fill(
        _ polylines: [Polyline],
        rule: CGPath.CGPathFillRule,
        color: CGColor,
        blendMode: CGBlendMode,
        shadow: CGShadow?
    ) {
        guard let coverage = ScanlineRasterizer.coverage(
            for: polylines,
            rule: rule,
            width: surface.width,
            height: surface.height
        ) else {
            return
        }
        if let shadow, blendMode != .clear {
            renderShadow(coverage, shadow: shadow, blendMode: blendMode)
        }

        let source: [Double]
        if blendMode == .clear {
            source = [0, 0, 0, 0]
        } else {
            guard let components = rgbaComponents(for: color) else { return }
            source = components
        }

        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let value = coverage[y * surface.width + x]
                let clipCoverage = clippingCoverage(atX: x, y: y)
                let combinedCoverage = (Int(value) * Int(clipCoverage) + 127) / 255
                guard combinedCoverage > 0 else { continue }
                composite(
                    source,
                    coverage: Double(combinedCoverage) / 255,
                    blendMode: blendMode,
                    x: x,
                    y: y
                )
            }
        }
    }

    /// Composites a displaced and blurred path mask before its source shape.
    /// - Parameters:
    ///   - coverage: The source shape's row-major coverage bytes.
    ///   - shadow: The device-space shadow settings captured by the draw command.
    ///   - blendMode: The compositing operation used for the shadow color.
    private func renderShadow(_ coverage: [UInt8], shadow: CGShadow, blendMode: CGBlendMode) {
        guard let source = rgbaComponents(for: shadow.color),
              coverage.count == surface.width * surface.height,
              shadow.offset.width.isFinite,
              shadow.offset.height.isFinite,
              shadow.blur.isFinite,
              shadow.blur >= 0 else {
            return
        }

        let shifted = shiftedCoverage(coverage, offset: shadow.offset)
        let blurred = gaussianBlur(shifted, sigma: shadow.blur)
        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let index = y * surface.width + x
                let clipCoverage = Double(clippingCoverage(atX: x, y: y)) / 255
                let combinedCoverage = blurred[index] * clipCoverage
                guard combinedCoverage > 0 else { continue }
                composite(source, coverage: combinedCoverage, blendMode: blendMode, x: x, y: y)
            }
        }
    }

    /// Moves a coverage mask with bilinear sampling to preserve fractional offsets.
    /// - Parameters:
    ///   - coverage: The source mask in row-major order.
    ///   - offset: The device-space displacement to apply.
    /// - Returns: The displaced mask as normalized coverage values.
    private func shiftedCoverage(_ coverage: [UInt8], offset: CGSize) -> [Double] {
        var shifted = [Double](repeating: 0, count: coverage.count)
        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let sourceX = Double(x) - offset.width
                let sourceY = Double(y) - offset.height
                guard sourceX > -1,
                      sourceX < Double(surface.width),
                      sourceY > -1,
                      sourceY < Double(surface.height) else {
                    continue
                }

                let left = Int(floor(sourceX))
                let top = Int(floor(sourceY))
                let fractionX = sourceX - Double(left)
                let fractionY = sourceY - Double(top)
                let topLeft = maskCoverage(coverage, x: left, y: top)
                let topRight = maskCoverage(coverage, x: left + 1, y: top)
                let bottomLeft = maskCoverage(coverage, x: left, y: top + 1)
                let bottomRight = maskCoverage(coverage, x: left + 1, y: top + 1)
                let upper = topLeft * (1 - fractionX) + topRight * fractionX
                let lower = bottomLeft * (1 - fractionX) + bottomRight * fractionX
                shifted[y * surface.width + x] = upper * (1 - fractionY) + lower * fractionY
            }
        }
        return shifted
    }

    /// Returns normalized mask coverage or zero outside the bitmap.
    /// - Parameters:
    ///   - coverage: The source mask in row-major order.
    ///   - x: The pixel column to sample.
    ///   - y: The pixel row to sample.
    /// - Returns: The coverage in the unit range.
    private func maskCoverage(_ coverage: [UInt8], x: Int, y: Int) -> Double {
        guard x >= 0, x < surface.width, y >= 0, y < surface.height else { return 0 }
        return Double(coverage[y * surface.width + x]) / 255
    }

    /// Applies a separable Gaussian filter to a row-major coverage mask.
    /// - Parameters:
    ///   - coverage: The normalized source coverage.
    ///   - sigma: The Gaussian standard deviation in pixels.
    /// - Returns: The blurred coverage mask.
    private func gaussianBlur(_ coverage: [Double], sigma: Double) -> [Double] {
        guard sigma > 0 else { return coverage }
        let radius = Int(min(ceil(sigma * 3), Double(max(surface.width, surface.height))))
        guard radius > 0 else { return coverage }
        let offsets = (-radius)...radius
        let weights = offsets.map { offset -> Double in
            let distance = Double(offset)
            return exp(-(distance * distance) / (2 * sigma * sigma))
        }
        let weightSum = weights.reduce(0, +)
        let normalizedWeights = weights.map { $0 / weightSum }
        var horizontal = [Double](repeating: 0, count: coverage.count)
        var blurred = [Double](repeating: 0, count: coverage.count)

        for y in 0..<surface.height {
            for x in 0..<surface.width {
                var value = 0.0
                for (weightIndex, offset) in offsets.enumerated() {
                    let sourceX = x + offset
                    guard sourceX >= 0, sourceX < surface.width else { continue }
                    value += coverage[y * surface.width + sourceX] * normalizedWeights[weightIndex]
                }
                horizontal[y * surface.width + x] = value
            }
        }

        for y in 0..<surface.height {
            for x in 0..<surface.width {
                var value = 0.0
                for (weightIndex, offset) in offsets.enumerated() {
                    let sourceY = y + offset
                    guard sourceY >= 0, sourceY < surface.height else { continue }
                    value += horizontal[sourceY * surface.width + x] * normalizedWeights[weightIndex]
                }
                blurred[y * surface.width + x] = value
            }
        }
        return blurred
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

    /// Rasterizes positioned glyphs and composites their coverage masks into the bitmap.
    /// - Parameters:
    ///   - glyphs: The glyph indices to render.
    ///   - positions: The corresponding text-space glyph origins.
    ///   - glyphBitmaps: The glyph masks captured with the draw command.
    ///   - characterSpacing: The additional horizontal distance between glyphs.
    ///   - textMatrix: The transform from text space to user space.
    ///   - textPosition: The text-space origin offset.
    ///   - ctm: The transform from user space to device space.
    ///   - color: The fill color used to paint glyph coverage.
    ///   - blendMode: The compositing operation applied to the glyphs.
    private func drawGlyphs(
        _ glyphs: [CGGlyph],
        positions: [CGPoint],
        glyphBitmaps: [CGGlyphBitmap?],
        characterSpacing: Double,
        textMatrix: CGAffineTransform,
        textPosition: CGPoint,
        ctm: CGAffineTransform,
        color: CGColor,
        blendMode: CGBlendMode
    ) {
        guard glyphs.count == positions.count,
              glyphs.count == glyphBitmaps.count else {
            return
        }

        let source: [Double]
        if blendMode == .clear {
            source = [0, 0, 0, 0]
        } else {
            guard let components = rgbaComponents(for: color) else { return }
            source = components
        }

        var visibleGlyphBitmaps: [(index: Int, bitmap: CGGlyphBitmap)] = []
        for (index, optionalBitmap) in glyphBitmaps.enumerated() {
            guard let bitmap = optionalBitmap,
                  bitmap.width > 0,
                  bitmap.height > 0 else {
                continue
            }
            visibleGlyphBitmaps.append((index, bitmap))
        }
        guard visibleGlyphBitmaps.isEmpty == false else { return }

        var atlasWidth = 1
        var atlasHeight = 1
        for entry in visibleGlyphBitmaps {
            let (glyphWidth, widthOverflow) = entry.bitmap.width.addingReportingOverflow(2)
            let (nextWidth, atlasWidthOverflow) = atlasWidth.addingReportingOverflow(glyphWidth)
            let (glyphHeight, heightOverflow) = entry.bitmap.height.addingReportingOverflow(2)
            guard widthOverflow == false,
                  atlasWidthOverflow == false,
                  heightOverflow == false else {
                return
            }
            atlasWidth = nextWidth
            atlasHeight = max(atlasHeight, glyphHeight)
        }
        let (atlasByteCount, byteCountOverflow) = atlasWidth.multipliedReportingOverflow(by: atlasHeight)
        guard byteCountOverflow == false else { return }

        var atlas = [UInt8](repeating: 0, count: atlasByteCount)
        var packedGlyphs: [(index: Int, bitmap: CGGlyphBitmap, atlasX: Int)] = []
        var atlasX = 1
        for entry in visibleGlyphBitmaps {
            for row in 0..<entry.bitmap.height {
                let sourceStart = row * entry.bitmap.width
                let destinationStart = (row + 1) * atlasWidth + atlasX
                let sourceRange = sourceStart..<(sourceStart + entry.bitmap.width)
                let destinationRange = destinationStart..<(destinationStart + entry.bitmap.width)
                atlas.replaceSubrange(destinationRange, with: entry.bitmap.coverage[sourceRange])
            }
            packedGlyphs.append((entry.index, entry.bitmap, atlasX))
            atlasX += entry.bitmap.width + 2
        }

        for entry in packedGlyphs {
            drawGlyphBitmap(
                entry.bitmap,
                atlas: atlas,
                atlasWidth: atlasWidth,
                atlasHeight: atlasHeight,
                atlasOriginX: entry.atlasX,
                atlasOriginY: 1,
                at: CGPoint(
                    x: positions[entry.index].x + Double(entry.index) * characterSpacing,
                    y: positions[entry.index].y
                ),
                textMatrix: textMatrix,
                textPosition: textPosition,
                ctm: ctm,
                source: source,
                blendMode: blendMode
            )
        }
    }

    /// Maps a glyph coverage bitmap through the text and current transforms.
    /// - Parameters:
    ///   - bitmap: The 8-bit glyph mask.
    ///   - atlas: The shared row-major 8-bit glyph atlas.
    ///   - atlasWidth: The number of atlas columns.
    ///   - atlasHeight: The number of atlas rows.
    ///   - atlasOriginX: The glyph mask's horizontal atlas offset.
    ///   - atlasOriginY: The glyph mask's vertical atlas offset.
    ///   - position: The glyph's text-space baseline position.
    ///   - textMatrix: The transform from text space to user space.
    ///   - textPosition: The text origin offset in user space.
    ///   - ctm: The transform from user space to device space.
    ///   - source: The normalized fill color.
    ///   - blendMode: The compositing operation.
    private func drawGlyphBitmap(
        _ bitmap: CGGlyphBitmap,
        atlas: [UInt8],
        atlasWidth: Int,
        atlasHeight: Int,
        atlasOriginX: Int,
        atlasOriginY: Int,
        at position: CGPoint,
        textMatrix: CGAffineTransform,
        textPosition: CGPoint,
        ctm: CGAffineTransform,
        source: [Double],
        blendMode: CGBlendMode
    ) {
        let (requiredByteCount, overflow) = atlasWidth.multipliedReportingOverflow(by: atlasHeight)
        let (glyphMaxX, xOverflow) = atlasOriginX.addingReportingOverflow(bitmap.width)
        let (glyphMaxY, yOverflow) = atlasOriginY.addingReportingOverflow(bitmap.height)
        guard overflow == false,
              xOverflow == false,
              yOverflow == false,
              atlas.count >= requiredByteCount,
              atlasOriginX >= 0,
              atlasOriginY >= 0,
              glyphMaxX <= atlasWidth,
              glyphMaxY <= atlasHeight else {
            return
        }

        let originX = position.x + Double(bitmap.xOffset)
        let originY = position.y + Double(bitmap.yOffset)
        let textPoints = [
            CGPoint(x: originX, y: originY),
            CGPoint(x: originX + Double(bitmap.width), y: originY),
            CGPoint(x: originX + Double(bitmap.width), y: originY + Double(bitmap.height)),
            CGPoint(x: originX, y: originY + Double(bitmap.height))
        ]
        let points = textPoints.map { point in
            let userPoint = point.applying(textMatrix)
            return CGPoint(
                x: userPoint.x + textPosition.x,
                y: userPoint.y + textPosition.y
            ).applying(ctm)
        }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }

        let origin = points[0]
        let horizontal = CGPoint(x: points[1].x - origin.x, y: points[1].y - origin.y)
        let vertical = CGPoint(x: points[3].x - origin.x, y: points[3].y - origin.y)
        let determinant = horizontal.x * vertical.y - horizontal.y * vertical.x
        guard determinant.isFinite, abs(determinant) > Double.ulpOfOne else { return }

        let minimumX = max(0, min(Double(surface.width), points.map(\.x).min() ?? 0))
        let minimumY = max(0, min(Double(surface.height), points.map(\.y).min() ?? 0))
        let maximumX = max(0, min(Double(surface.width), points.map(\.x).max() ?? 0))
        let maximumY = max(0, min(Double(surface.height), points.map(\.y).max() ?? 0))
        let firstX = Int(floor(minimumX))
        let firstY = Int(floor(minimumY))
        let lastX = Int(ceil(maximumX))
        let lastY = Int(ceil(maximumY))
        guard firstX < lastX, firstY < lastY else { return }

        for y in firstY..<lastY {
            for x in firstX..<lastX {
                let clipCoverage = clippingCoverage(atX: x, y: y)
                guard clipCoverage > 0 else { continue }
                let deltaX = Double(x) + 0.5 - origin.x
                let deltaY = Double(y) + 0.5 - origin.y
                let u = (deltaX * vertical.y - deltaY * vertical.x) / determinant
                let v = (horizontal.x * deltaY - horizontal.y * deltaX) / determinant
                guard u >= 0, u < 1, v >= 0, v < 1 else { continue }

                let maskCoverage = sampleGlyphCoverage(
                    atlas,
                    x: u * Double(bitmap.width),
                    y: v * Double(bitmap.height),
                    atlasWidth: atlasWidth,
                    atlasOriginX: atlasOriginX,
                    atlasOriginY: atlasOriginY,
                    width: bitmap.width,
                    height: bitmap.height
                )
                let combinedCoverage = maskCoverage * Double(clipCoverage) / 255
                guard combinedCoverage > 0 else { continue }
                composite(source, coverage: combinedCoverage, blendMode: blendMode, x: x, y: y)
            }
        }
    }

    /// Bilinearly samples the 8-bit coverage mask at a bitmap-space coordinate.
    /// - Parameters:
    ///   - atlas: The row-major atlas coverage values.
    ///   - x: The horizontal sample coordinate measured from the first pixel edge.
    ///   - y: The vertical sample coordinate measured from the first pixel edge.
    ///   - atlasWidth: The number of atlas columns.
    ///   - atlasOriginX: The horizontal offset of the glyph region.
    ///   - atlasOriginY: The vertical offset of the glyph region.
    ///   - width: The bitmap width.
    ///   - height: The bitmap height.
    /// - Returns: The interpolated coverage from zero through 255.
    private func sampleGlyphCoverage(
        _ atlas: [UInt8],
        x: Double,
        y: Double,
        atlasWidth: Int,
        atlasOriginX: Int,
        atlasOriginY: Int,
        width: Int,
        height: Int
    ) -> Double {
        let sampleX = x - 0.5
        let sampleY = y - 0.5
        let firstX = Int(floor(sampleX))
        let firstY = Int(floor(sampleY))
        let fractionX = sampleX - Double(firstX)
        let fractionY = sampleY - Double(firstY)

        let value: (Int, Int) -> Double = { x, y in
            guard x >= 0, x < width, y >= 0, y < height else { return 0 }
            return Double(atlas[(atlasOriginY + y) * atlasWidth + atlasOriginX + x])
        }

        let top = value(firstX, firstY) * (1 - fractionX)
            + value(firstX + 1, firstY) * fractionX
        let bottom = value(firstX, firstY + 1) * (1 - fractionX)
            + value(firstX + 1, firstY + 1) * fractionX
        return top * (1 - fractionY) + bottom * fractionY
    }

    /// Draws an image into an affine destination quad using inverse-coordinate sampling.
    /// - Parameters:
    ///   - image: The immutable source bitmap.
    ///   - destination: The transformed corners in top-left, top-right, bottom-right, bottom-left order.
    ///   - interpolationQuality: The sampling mode used to scale the image.
    ///   - byTiling: Whether source pixels repeat along the destination axes.
    ///   - blendMode: The compositing operation applied to sampled pixels.
    private func drawImage(
        _ image: CGImageSnapshot,
        destination: [CGPoint],
        interpolationQuality: CGInterpolationQuality,
        byTiling: Bool,
        blendMode: CGBlendMode
    ) {
        guard image.width > 0,
              image.height > 0,
              image.bitsPerComponent == 8,
              image.bitsPerPixel > 0,
              image.bitsPerPixel.isMultiple(of: 8),
              image.bytesPerRow > 0,
              [.byteOrderDefault, .byteOrder32Big, .byteOrder32Little].contains(image.bitmapInfo),
              destination.count == 4,
              let data = image.data,
              let colorSpaceModel = image.colorSpace?.model else {
            return
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let (minimumBytesPerRow, rowOverflow) = image.width.multipliedReportingOverflow(by: bytesPerPixel)
        let (requiredByteCount, dataOverflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard rowOverflow == false,
              dataOverflow == false,
              image.bytesPerRow >= minimumBytesPerRow,
              data.count >= requiredByteCount,
              colorSpaceModel == .rgb || colorSpaceModel == .gray || colorSpaceModel == .cmyk else {
            return
        }

        let points = destination
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        let origin = points[0]
        let horizontal = CGPoint(x: points[1].x - origin.x, y: points[1].y - origin.y)
        let vertical = CGPoint(x: points[3].x - origin.x, y: points[3].y - origin.y)
        let determinant = horizontal.x * vertical.y - horizontal.y * vertical.x
        guard determinant.isFinite, abs(determinant) > Double.ulpOfOne else { return }

        let minimumX = max(0, min(Double(surface.width), points.map(\.x).min() ?? 0))
        let minimumY = max(0, min(Double(surface.height), points.map(\.y).min() ?? 0))
        let maximumX = max(0, min(Double(surface.width), points.map(\.x).max() ?? 0))
        let maximumY = max(0, min(Double(surface.height), points.map(\.y).max() ?? 0))
        let firstX = Int(floor(minimumX))
        let firstY = Int(floor(minimumY))
        let lastX = Int(ceil(maximumX))
        let lastY = Int(ceil(maximumY))
        guard firstX < lastX, firstY < lastY else { return }

        let horizontalLength = hypot(horizontal.x, horizontal.y)
        let verticalLength = hypot(vertical.x, vertical.y)
        guard horizontalLength.isFinite,
              verticalLength.isFinite,
              horizontalLength > 0,
              verticalLength > 0 else {
            return
        }

        for y in firstY..<lastY {
            for x in firstX..<lastX {
                let clipCoverage = clippingCoverage(atX: x, y: y)
                guard clipCoverage > 0 else { continue }
                let deltaX = Double(x) + 0.5 - origin.x
                let deltaY = Double(y) + 0.5 - origin.y
                let u = (deltaX * vertical.y - deltaY * vertical.x) / determinant
                let v = (horizontal.x * deltaY - horizontal.y * deltaX) / determinant
                guard u >= 0, u < 1, v >= 0, v < 1 else { continue }

                let sourceX = byTiling ? u * horizontalLength : u * Double(image.width)
                let sourceY = byTiling
                    ? (1 - v) * verticalLength
                    : (1 - v) * Double(image.height)
                guard let source = sampleImage(
                    image,
                    x: sourceX,
                    y: sourceY,
                    bytesPerPixel: bytesPerPixel,
                    nearest: interpolationQuality == .none,
                    tiling: byTiling
                ) else {
                    continue
                }

                composite(
                    source,
                    coverage: Double(clipCoverage) / 255,
                    blendMode: blendMode,
                    x: x,
                    y: y
                )
            }
        }
    }

    /// Samples one source coordinate using nearest-neighbor or bilinear interpolation.
    /// - Parameters:
    ///   - image: The source bitmap.
    ///   - x: The horizontal source coordinate measured from the first pixel edge.
    ///   - y: The vertical source coordinate measured from the first pixel edge.
    ///   - bytesPerPixel: The number of bytes occupied by one source pixel.
    ///   - nearest: Whether to choose the nearest source pixel instead of interpolating.
    ///   - tiling: Whether sample coordinates wrap around the image edges.
    /// - Returns: A normalized, unpremultiplied RGBA sample, or nil for unsupported data.
    private func sampleImage(
        _ image: CGImageSnapshot,
        x: Double,
        y: Double,
        bytesPerPixel: Int,
        nearest: Bool,
        tiling: Bool
    ) -> [Double]? {
        guard let data = image.data else { return nil }
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        let sampleX = tiling ? positiveRemainder(x, modulus: imageWidth) : min(imageWidth, max(0, x))
        let sampleY = tiling ? positiveRemainder(y, modulus: imageHeight) : min(imageHeight, max(0, y))

        if nearest {
            let pixelX = min(image.width - 1, Int(floor(sampleX)))
            let pixelY = min(image.height - 1, Int(floor(sampleY)))
            return imagePixel(image, data: data, x: pixelX, y: pixelY, bytesPerPixel: bytesPerPixel)
        }

        let centeredX = sampleX - 0.5
        let centeredY = sampleY - 0.5
        let floorX = Int(floor(centeredX))
        let floorY = Int(floor(centeredY))
        let fractionX = centeredX - Double(floorX)
        let fractionY = centeredY - Double(floorY)
        let x0 = imageIndex(floorX, length: image.width, tiling: tiling)
        let x1 = imageIndex(floorX + 1, length: image.width, tiling: tiling)
        let y0 = imageIndex(floorY, length: image.height, tiling: tiling)
        let y1 = imageIndex(floorY + 1, length: image.height, tiling: tiling)

        guard let topLeft = imagePixel(image, data: data, x: x0, y: y0, bytesPerPixel: bytesPerPixel),
              let topRight = imagePixel(image, data: data, x: x1, y: y0, bytesPerPixel: bytesPerPixel),
              let bottomLeft = imagePixel(image, data: data, x: x0, y: y1, bytesPerPixel: bytesPerPixel),
              let bottomRight = imagePixel(image, data: data, x: x1, y: y1, bytesPerPixel: bytesPerPixel) else {
            return nil
        }

        let sampledPixels: [[Double]] = [topLeft, topRight, bottomLeft, bottomRight]
        let premultipliedPixels: [[Double]] = sampledPixels.map { pixel in
            let alpha = pixel[3]
            return [pixel[0] * alpha, pixel[1] * alpha, pixel[2] * alpha, alpha]
        }
        let leftWeight = 1 - fractionX
        let interpolated = (0..<4).map { component in
            let top = premultipliedPixels[0][component] * leftWeight
                + premultipliedPixels[1][component] * fractionX
            let bottom = premultipliedPixels[2][component] * leftWeight
                + premultipliedPixels[3][component] * fractionX
            return top * (1 - fractionY) + bottom * fractionY
        }
        guard interpolated[3] > 0 else { return [0, 0, 0, 0] }
        return [
            min(1, interpolated[0] / interpolated[3]),
            min(1, interpolated[1] / interpolated[3]),
            min(1, interpolated[2] / interpolated[3]),
            interpolated[3]
        ]
    }

    /// Decodes one supported 8-bit RGB, grayscale, or CMYK source pixel.
    /// - Parameters:
    ///   - image: The source image metadata.
    ///   - data: The validated image bytes.
    ///   - x: The zero-based source column.
    ///   - y: The zero-based source row.
    ///   - bytesPerPixel: The number of bytes occupied by one source pixel.
    /// - Returns: Four normalized, unpremultiplied RGBA components.
    private func imagePixel(
        _ image: CGImageSnapshot,
        data: Data,
        x: Int,
        y: Int,
        bytesPerPixel: Int
    ) -> [Double]? {
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        guard offset >= 0, offset + bytesPerPixel <= data.count else { return nil }
        let bytes = (0..<bytesPerPixel).map { Double(data[offset + $0]) / 255 }
        let isLittleEndian = image.bitmapInfo == .byteOrder32Little
        let rgba: [Double]

        switch image.colorSpace?.model {
        case .rgb:
            guard let indices = rgbComponentIndices(
                alphaInfo: image.alphaInfo,
                byteCount: bytesPerPixel,
                littleEndian: isLittleEndian
            ) else {
                return nil
            }
            rgba = [
                bytes[indices.red],
                bytes[indices.green],
                bytes[indices.blue],
                indices.alpha.map { bytes[$0] } ?? 1
            ]
        case .gray:
            guard bytes.first != nil else { return nil }
            let alphaIndex: Int?
            switch image.alphaInfo {
            case .first, .premultipliedFirst:
                alphaIndex = 0
            case .last, .premultipliedLast:
                alphaIndex = bytesPerPixel - 1
            default:
                alphaIndex = nil
            }
            guard let grayIndex = alphaIndex == 0 ? bytes.dropFirst().first : bytes.first else { return nil }
            rgba = [grayIndex, grayIndex, grayIndex, alphaIndex.map { bytes[$0] } ?? 1]
        case .cmyk:
            let componentOffset = image.alphaInfo == .first || image.alphaInfo == .premultipliedFirst ? 1 : 0
            guard bytes.count >= componentOffset + 4 else { return nil }
            let cyan = bytes[componentOffset]
            let magenta = bytes[componentOffset + 1]
            let yellow = bytes[componentOffset + 2]
            let black = bytes[componentOffset + 3]
            let alphaIndex: Int?
            switch image.alphaInfo {
            case .first, .premultipliedFirst:
                alphaIndex = 0
            case .last, .premultipliedLast:
                alphaIndex = componentOffset + 4
            default:
                alphaIndex = nil
            }
            if let alphaIndex, !bytes.indices.contains(alphaIndex) {
                return nil
            }
            rgba = [
                (1 - cyan) * (1 - black),
                (1 - magenta) * (1 - black),
                (1 - yellow) * (1 - black),
                alphaIndex.map { bytes[$0] } ?? 1
            ]
        case .deviceN, .lab, .none:
            return nil
        }

        guard rgba.allSatisfy(\.isFinite) else { return nil }
        var result = rgba.map { min(1, max(0, $0)) }
        if image.alphaInfo == .premultipliedFirst || image.alphaInfo == .premultipliedLast {
            let alpha = result[3]
            if alpha > 0 {
                result[0] = min(1, result[0] / alpha)
                result[1] = min(1, result[1] / alpha)
                result[2] = min(1, result[2] / alpha)
            }
        }
        if let sourceColorSpace = image.colorSpace,
           sourceColorSpace == .sRGB || sourceColorSpace == .genericRGBLinear {
            guard let color = CGColor(colorSpace: sourceColorSpace, components: result),
                  let converted = color.converted(to: .genericRGBLinear) else {
                return nil
            }
            result = converted.components
        }
        return result
    }

    /// Resolves RGB and optional alpha byte positions for a bitmap layout.
    /// - Parameters:
    ///   - alphaInfo: The source alpha placement.
    ///   - byteCount: The number of bytes in a pixel.
    ///   - littleEndian: Whether 32-bit components use little-endian byte order.
    /// - Returns: The RGB byte indices and optional alpha index when supported.
    private func rgbComponentIndices(
        alphaInfo: CGImageAlphaInfo,
        byteCount: Int,
        littleEndian: Bool
    ) -> (red: Int, green: Int, blue: Int, alpha: Int?)? {
        switch alphaInfo {
        case .first, .premultipliedFirst:
            guard byteCount >= 4 else { return nil }
            return littleEndian ? (2, 1, 0, 3) : (1, 2, 3, 0)
        case .last, .premultipliedLast:
            guard byteCount >= 4 else { return nil }
            return littleEndian ? (3, 2, 1, 0) : (0, 1, 2, 3)
        case .noneSkipFirst:
            guard byteCount >= 4 else { return nil }
            return littleEndian ? (2, 1, 0, nil) : (1, 2, 3, nil)
        case .noneSkipLast:
            guard byteCount >= 4 else { return nil }
            return littleEndian ? (3, 2, 1, nil) : (0, 1, 2, nil)
        case .none:
            guard byteCount >= 3 else { return nil }
            if byteCount == 3 {
                return (0, 1, 2, nil)
            }
            return littleEndian ? (2, 1, 0, nil) : (0, 1, 2, nil)
        case .alphaOnly:
            return nil
        }
    }

    /// Wraps or clamps a pixel index to the valid image range.
    /// - Parameters:
    ///   - index: The source pixel index.
    ///   - length: The image dimension for this axis.
    ///   - tiling: Whether to wrap beyond the image edges.
    /// - Returns: A valid pixel index.
    private func imageIndex(_ index: Int, length: Int, tiling: Bool) -> Int {
        guard tiling else { return min(length - 1, max(0, index)) }
        let remainder = index % length
        return remainder >= 0 ? remainder : remainder + length
    }

    /// Returns a nonnegative remainder for a floating-point source coordinate.
    /// - Parameters:
    ///   - value: The source coordinate.
    ///   - modulus: The positive image dimension.
    /// - Returns: A value from zero up to, but not including, the modulus.
    private func positiveRemainder(_ value: Double, modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    /// Applies a blend or Porter-Duff operation using premultiplied pixel storage.
    /// - Parameters:
    ///   - source: The normalized, unpremultiplied RGBA source components.
    ///   - coverage: The fraction of the destination pixel covered by the operation.
    ///   - blendMode: The requested compositing operation.
    ///   - x: The destination pixel column.
    ///   - y: The destination pixel row.
    private func composite(
        _ source: [Double],
        coverage: Double,
        blendMode: CGBlendMode,
        x: Int,
        y: Int
    ) {
        guard let destination = surface.pixel(x: x, y: y) else { return }
        let sourceAlpha = source[3]
        let destinationAlpha = Double(destination.alpha) / 255
        let sourcePremultiplied = [source[0], source[1], source[2]].map { $0 * sourceAlpha }
        var destinationPremultiplied = [
            Double(destination.red) / 255,
            Double(destination.green) / 255,
            Double(destination.blue) / 255
        ]
        if surface.colorSpace == .sRGB {
            let straightDestination = destinationAlpha == 0
                ? [0, 0, 0]
                : destinationPremultiplied.map { $0 / destinationAlpha }
            guard let storedColor = CGColor(
                colorSpace: .sRGB,
                components: straightDestination + [destinationAlpha]
            ),
            let linearColor = storedColor.converted(to: .genericRGBLinear) else {
                return
            }
            destinationPremultiplied = linearColor.components.prefix(3).map { $0 * destinationAlpha }
        }
        let result: [Double]
        let resultAlpha: Double

        switch blendMode {
        case .clear:
            result = [0, 0, 0]
            resultAlpha = 0
        case .copy:
            result = sourcePremultiplied
            resultAlpha = sourceAlpha
        case .sourceIn:
            result = sourcePremultiplied.map { $0 * destinationAlpha }
            resultAlpha = sourceAlpha * destinationAlpha
        case .sourceOut:
            result = sourcePremultiplied.map { $0 * (1 - destinationAlpha) }
            resultAlpha = sourceAlpha * (1 - destinationAlpha)
        case .sourceAtop:
            result = zip(sourcePremultiplied, destinationPremultiplied).map {
                $0 * destinationAlpha + $1 * (1 - sourceAlpha)
            }
            resultAlpha = destinationAlpha
        case .destinationOver:
            result = zip(sourcePremultiplied, destinationPremultiplied).map {
                $1 + $0 * (1 - destinationAlpha)
            }
            resultAlpha = destinationAlpha + sourceAlpha * (1 - destinationAlpha)
        case .destinationIn:
            result = destinationPremultiplied.map { $0 * sourceAlpha }
            resultAlpha = destinationAlpha * sourceAlpha
        case .destinationOut:
            result = destinationPremultiplied.map { $0 * (1 - sourceAlpha) }
            resultAlpha = destinationAlpha * (1 - sourceAlpha)
        case .destinationAtop:
            result = zip(sourcePremultiplied, destinationPremultiplied).map {
                $1 * sourceAlpha + $0 * (1 - destinationAlpha)
            }
            resultAlpha = sourceAlpha
        case .xor:
            result = zip(sourcePremultiplied, destinationPremultiplied).map {
                $0 * (1 - destinationAlpha) + $1 * (1 - sourceAlpha)
            }
            resultAlpha = sourceAlpha * (1 - destinationAlpha) + destinationAlpha * (1 - sourceAlpha)
        default:
            let backdrop = destinationAlpha == 0
                ? [0, 0, 0]
                : destinationPremultiplied.map { $0 / destinationAlpha }
            let blended = zip(backdrop, source.prefix(3)).map {
                blendChannel(blendMode, backdrop: $0, source: $1)
            }
            result = (0..<3).map { index in
                (1 - sourceAlpha) * destinationPremultiplied[index]
                    + (1 - destinationAlpha) * sourcePremultiplied[index]
                    + sourceAlpha * destinationAlpha * blended[index]
            }
            resultAlpha = sourceAlpha + destinationAlpha - sourceAlpha * destinationAlpha
        }

        let remainingCoverage = 1 - coverage
        let outputAlpha = resultAlpha * coverage + destinationAlpha * remainingCoverage
        var outputColor = (0..<3).map { index in
            result[index] * coverage + destinationPremultiplied[index] * remainingCoverage
        }
        if surface.colorSpace == .sRGB, outputAlpha > 0 {
            let straightOutput = outputColor.map { $0 / outputAlpha }
            guard let linearColor = CGColor(
                colorSpace: .genericRGBLinear,
                components: straightOutput + [outputAlpha]
            ),
            let srgbColor = linearColor.converted(to: .sRGB) else {
                return
            }
            outputColor = srgbColor.components.prefix(3).map { $0 * outputAlpha }
        }

        let output = PixelSurface.Pixel(
            red: channel(outputColor[0]),
            green: channel(outputColor[1]),
            blue: channel(outputColor[2]),
            alpha: channel(outputAlpha)
        )
        surface.setPixel(output, x: x, y: y)
    }

    /// Computes one separable blend channel; nonseparable modes use normal blending.
    /// - Parameters:
    ///   - mode: The requested blend mode.
    ///   - backdrop: The unpremultiplied destination channel.
    ///   - source: The unpremultiplied source channel.
    /// - Returns: The blended channel value in the unit range.
    private func blendChannel(_ mode: CGBlendMode, backdrop: Double, source: Double) -> Double {
        switch mode {
        case .normal, .hue, .saturation, .color, .luminosity:
            return source
        case .multiply:
            return backdrop * source
        case .screen:
            return backdrop + source - backdrop * source
        case .overlay:
            return backdrop <= 0.5
                ? 2 * backdrop * source
                : 1 - 2 * (1 - backdrop) * (1 - source)
        case .darken:
            return min(backdrop, source)
        case .lighten:
            return max(backdrop, source)
        case .colorDodge:
            return source >= 1 ? 1 : min(1, backdrop / (1 - source))
        case .colorBurn:
            return source <= 0 ? 0 : 1 - min(1, (1 - backdrop) / source)
        case .softLight:
            if source <= 0.5 {
                return backdrop - (1 - 2 * source) * backdrop * (1 - backdrop)
            } else {
                let curve = backdrop <= 0.25
                    ? ((16 * backdrop - 12) * backdrop + 4) * backdrop
                    : backdrop.squareRoot()
                return backdrop + (2 * source - 1) * (curve - backdrop)
            }
        case .hardLight:
            return source <= 0.5
                ? 2 * backdrop * source
                : 1 - 2 * (1 - backdrop) * (1 - source)
        case .difference:
            return abs(backdrop - source)
        case .exclusion:
            return backdrop + source - 2 * backdrop * source
        case .plusDarker:
            return max(0, backdrop + source - 1)
        case .plusLighter:
            return min(1, backdrop + source)
        case .clear, .copy, .sourceIn, .sourceOut, .sourceAtop,
             .destinationOver, .destinationIn, .destinationOut, .destinationAtop, .xor:
            return source
        }
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
        let convertedColor: CGColor
        if colorSpace == .sRGB || colorSpace == .genericRGBLinear {
            guard let converted = color.converted(to: .genericRGBLinear) else { return nil }
            convertedColor = converted
        } else {
            convertedColor = color
        }

        let components: [Double]
        switch colorSpace.model {
        case .rgb:
            guard convertedColor.components.count == 4 else { return nil }
            components = convertedColor.components
        case .gray:
            guard convertedColor.components.count == 2 else { return nil }
            components = [
                convertedColor.components[0],
                convertedColor.components[0],
                convertedColor.components[0],
                convertedColor.components[1]
            ]
        case .cmyk:
            guard convertedColor.components.count == 5 else { return nil }
            let black = convertedColor.components[3]
            components = [
                (1 - convertedColor.components[0]) * (1 - black),
                (1 - convertedColor.components[1]) * (1 - black),
                (1 - convertedColor.components[2]) * (1 - black),
                convertedColor.components[4]
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
