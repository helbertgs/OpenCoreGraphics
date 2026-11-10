import Foundation

/// Renders aligned rectangular fills into a bitmap surface without GPU dependencies.
final class SoftwareRenderer: CGRenderBackend {
    /// The bitmap that receives rendered pixels.
    private let surface: PixelSurface

    /// Creates a renderer for the supplied pixel storage.
    /// - Parameter surface: The bitmap that receives rendered output.
    init(surface: PixelSurface) {
        self.surface = surface
    }

    /// Executes the supported rectangle fill commands in submission order.
    /// - Parameters:
    ///   - commands: The operations to render.
    ///   - size: The bitmap dimensions in pixels.
    func execute(_ commands: [DrawCommand], size: CGSize) {
        for command in commands {
            guard case let .fillPath(path, _, color, blendMode) = command,
                  let rectangle = alignedRectangle(in: path) else {
                continue
            }
            fill(rectangle, color: color, blendMode: blendMode)
        }
    }

    /// Returns a snapshot of the rendered bitmap bytes.
    /// - Returns: A copy of all pixel rows, including row padding.
    func readPixels() -> Data {
        Data(bytes: surface.dataPointer, count: surface.byteCount)
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
            let clearPixel = PixelSurface.Pixel(red: 0, green: 0, blue: 0, alpha: 0)
            for y in firstY..<lastY {
                for x in firstX..<lastX {
                    surface.setPixel(clearPixel, x: x, y: y)
                }
            }
            return
        }
        guard blendMode == .normal,
              let source = rgbaComponents(for: color) else {
            return
        }

        let sourceAlpha = source[3]
        for y in firstY..<lastY {
            for x in firstX..<lastX {
                guard let destination = surface.pixel(x: x, y: y) else { continue }
                let destinationAlpha = Double(destination.alpha) / 255
                let remainingAlpha = 1 - sourceAlpha
                let outputAlpha = sourceAlpha + destinationAlpha * remainingAlpha
                let output = PixelSurface.Pixel(
                    red: channel(source[0] * sourceAlpha + Double(destination.red) / 255 * remainingAlpha),
                    green: channel(source[1] * sourceAlpha + Double(destination.green) / 255 * remainingAlpha),
                    blue: channel(source[2] * sourceAlpha + Double(destination.blue) / 255 * remainingAlpha),
                    alpha: channel(outputAlpha)
                )
                surface.setPixel(output, x: x, y: y)
            }
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
