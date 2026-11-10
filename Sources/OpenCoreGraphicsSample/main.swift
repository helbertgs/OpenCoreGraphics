import class Foundation.FileManager
import Foundation
import OpenCoreGraphics

let window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 512, height: 512), title: "OpenCoreGraphics Sample")
let softwareImage: CGImage?

if CommandLine.arguments.contains("--software")
    || CommandLine.arguments.contains("--test-shadow")
    || CommandLine.arguments.contains("--test-gradient") {
    guard let softwareContext = CGContext(
        data: nil,
        width: 512,
        height: 512,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: .sRGB,
        bitmapInfo: 0
    ) else {
        preconditionFailure("The software sample bitmap context could not be created.")
    }

    if CommandLine.arguments.contains("--test-gradient") {
        drawGradientSample(in: softwareContext)
    } else if CommandLine.arguments.contains("--test-shadow") {
        softwareContext.setShadow(
            offset: CGSize(width: 14, height: 14),
            blur: 8,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.65)
        )
        softwareContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        softwareContext.fill(CGRect(x: 120, y: 120, width: 260, height: 220))
    } else if CommandLine.arguments.contains("--test-clip") {
        softwareContext.saveGState()
        softwareContext.clip(to: CGRect(x: 100, y: 100, width: 300, height: 300))
        softwareContext.beginPath()
        softwareContext.addPath(CGPath(ellipseIn: CGRect(x: 150, y: 80, width: 300, height: 400)))
        softwareContext.clip()
        softwareContext.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.4, alpha: 1))
        softwareContext.fill(CGRect(x: 50, y: 50, width: 400, height: 400))
        softwareContext.restoreGState()
    } else if CommandLine.arguments.contains("--test-blend-modes") {
        softwareContext.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        softwareContext.fill(CGRect(x: 70, y: 80, width: 370, height: 350))
        softwareContext.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.5))
        softwareContext.setBlendMode(.normal)
        softwareContext.fill(CGRect(x: 90, y: 120, width: 160, height: 230))
        softwareContext.setBlendMode(.multiply)
        softwareContext.fill(CGRect(x: 270, y: 120, width: 160, height: 230))
    } else {
        softwareContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        softwareContext.fill(CGRect(x: 20, y: 20, width: 150, height: 200))

        softwareContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        softwareContext.fill(CGRect(x: 200, y: 100, width: 150, height: 200))

        softwareContext.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1))
        softwareContext.fillEllipse(in: CGRect(x: 180, y: 340, width: 150, height: 100))
    }
    softwareContext.flush()

    guard let image = softwareContext.makeImage() else {
        preconditionFailure("The software sample bitmap image could not be created.")
    }
    softwareImage = image
} else {
    softwareImage = nil
}

window.display = {
    let cgContext = window.cgContext

    if let softwareImage {
        cgContext.saveGState()
        cgContext.translateBy(x: 0, y: Double(cgContext.height))
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.interpolationQuality = .none
        cgContext.draw(
            softwareImage,
            in: CGRect(x: 0, y: 0, width: Double(cgContext.width), height: Double(cgContext.height))
        )
        cgContext.restoreGState()
        return
    }

    if CommandLine.arguments.contains("--test-clip") {
        cgContext.saveGState()
        cgContext.clip(to: CGRect(x: 100, y: 100, width: 300, height: 300))
        cgContext.beginPath()
        cgContext.addPath(CGPath(ellipseIn: CGRect(x: 150, y: 80, width: 300, height: 400)))
        cgContext.clip()
        cgContext.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.4, alpha: 1))
        cgContext.fill(CGRect(x: 50, y: 50, width: 400, height: 400))
        cgContext.restoreGState()
        return
    }

    if CommandLine.arguments.contains("--test-blend-modes") {
        cgContext.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        cgContext.fill(CGRect(x: 70, y: 80, width: 370, height: 350))
        cgContext.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.5))
        cgContext.setBlendMode(.normal)
        cgContext.fill(CGRect(x: 90, y: 120, width: 160, height: 230))
        cgContext.setBlendMode(.multiply)
        cgContext.fill(CGRect(x: 270, y: 120, width: 160, height: 230))
        return
    }

    if CommandLine.arguments.contains("--test-image") {
        guard let imageURL = Bundle.module.url(forResource: "orientation-test", withExtension: "bmp"),
              let image = CGImage(url: imageURL.path) else {
            preconditionFailure("The bundled orientation test image could not be loaded.")
        }
        cgContext.interpolationQuality = .none
        cgContext.draw(image, in: CGRect(x: 300, y: 300, width: 128, height: 128))
        return
    }

    if CommandLine.arguments.contains("--test-stroke") {
        cgContext.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        cgContext.setLineWidth(8)
        cgContext.beginPath()
        cgContext.move(to: CGPoint(x: 100, y: 100))
        cgContext.addLine(to: CGPoint(x: 412, y: 100))
        cgContext.addLine(to: CGPoint(x: 412, y: 412))
        cgContext.addLine(to: CGPoint(x: 100, y: 412))
        cgContext.closePath()
        cgContext.strokePath()
        return
    }

    if CommandLine.arguments.contains("--test-context-shapes") {
        cgContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        cgContext.fillEllipse(in: CGRect(x: 40, y: 70, width: 160, height: 110))

        cgContext.setStrokeColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        cgContext.setLineWidth(8)
        cgContext.strokeEllipse(in: CGRect(x: 300, y: 70, width: 160, height: 110))

        cgContext.setStrokeColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        cgContext.strokeLineSegments(between: [
            CGPoint(x: 60, y: 300),
            CGPoint(x: 220, y: 360),
            CGPoint(x: 290, y: 360),
            CGPoint(x: 450, y: 300)
        ])
        return
    }

    if CommandLine.arguments.contains("--test-rendering") {
        var windingStar = CGPath()
        windingStar.move(to: CGPoint(x: 128, y: 38))
        windingStar.addLine(to: CGPoint(x: 181, y: 201))
        windingStar.addLine(to: CGPoint(x: 42, y: 100))
        windingStar.addLine(to: CGPoint(x: 214, y: 100))
        windingStar.addLine(to: CGPoint(x: 75, y: 201))
        windingStar.closeSubpath()

        var evenOddStar = CGPath()
        evenOddStar.move(to: CGPoint(x: 384, y: 38))
        evenOddStar.addLine(to: CGPoint(x: 437, y: 201))
        evenOddStar.addLine(to: CGPoint(x: 298, y: 100))
        evenOddStar.addLine(to: CGPoint(x: 470, y: 100))
        evenOddStar.addLine(to: CGPoint(x: 331, y: 201))
        evenOddStar.closeSubpath()

        cgContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        cgContext.beginPath()
        cgContext.addPath(windingStar)
        cgContext.fillPath(using: .winding)

        cgContext.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        cgContext.beginPath()
        cgContext.addPath(evenOddStar)
        cgContext.fillPath(using: .evenOdd)
        return
    }

    drawTextSample(in: cgContext)
}

window.makeKeyAndOrderFront()

/// Draws linear and radial gradients in clipped sample regions.
/// - Parameter context: The context used to render the gradient demonstration.
private func drawGradientSample(in context: CGContext) {
    guard let linearGradient = CGGradient(
        colors: [
            CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
            CGColor(red: 0.2, green: 0.8, blue: 0.7, alpha: 1),
            CGColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        ],
        locations: [0, 0.55, 1]
    ), let radialGradient = CGGradient(
        colors: [.white, CGColor(red: 1, green: 0.2, blue: 0.15, alpha: 1)],
        locations: [0, 1]
    ) else {
        preconditionFailure("The sample gradients could not be created.")
    }

    let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    let linearBounds = CGRect(x: 32, y: 120, width: 208, height: 272)
    context.saveGState()
    context.clip(to: linearBounds)
    context.drawLinearGradient(
        linearGradient,
        start: CGPoint(x: linearBounds.minX, y: linearBounds.midY),
        end: CGPoint(x: linearBounds.maxX, y: linearBounds.midY),
        options: options
    )
    context.restoreGState()

    let radialBounds = CGRect(x: 272, y: 120, width: 208, height: 272)
    context.saveGState()
    context.clip(to: radialBounds)
    context.drawRadialGradient(
        radialGradient,
        startCenter: CGPoint(x: radialBounds.midX, y: radialBounds.midY),
        startRadius: 0,
        endCenter: CGPoint(x: radialBounds.midX, y: radialBounds.midY),
        endRadius: 100,
        options: options
    )
    context.restoreGState()
}

/// Draws the requested phrase with a system-installed TrueType font.
/// - Parameter context: The context used to render the text demonstration.
private func drawTextSample(in context: CGContext) {
    let font = sampleFont()
    let phrase = "OpenCoreGraphics"
    let fontSize = 24.0
    guard font.unitsPerEm > 0 else {
        preconditionFailure("The sample font has invalid units-per-em metrics.")
    }

    var glyphs: [CGGlyph] = []
    for character in phrase {
        guard let glyph = font.glyph(for: character) else {
            preconditionFailure("The sample font does not contain every character in \(phrase).")
        }
        glyphs.append(glyph)
    }

    var positions: [OpenCoreGraphics.CGPoint] = []
    var penX = 0.0
    for glyph in glyphs {
        positions.append(CGPoint(x: penX, y: 0))
        guard let advance = font.advance(for: glyph) else {
            preconditionFailure("The sample font does not provide an advance for a rendered glyph.")
        }
        penX += advance * fontSize / Double(font.unitsPerEm)
    }

    context.setFont(font)
    context.setFontSize(fontSize)
    context.setCharacterSpacing(0)
    context.textPosition = CGPoint(x: (Double(context.width) - penX) / 2, y: 256)
    context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 1, alpha: 1))
    context.showGlyphs(glyphs, at: positions)
}

/// Finds a locally installed font suitable for the sample phrase.
/// - Returns: The loaded font, or terminates with an actionable error.
private func sampleFont() -> CGFont {
    let fontPaths: [String]
    if let fontArgument = CommandLine.arguments.firstIndex(of: "--font") {
        guard fontArgument + 1 < CommandLine.arguments.count else {
            preconditionFailure("Pass a TrueType font path after --font.")
        }
        fontPaths = [CommandLine.arguments[fontArgument + 1]]
    } else {
        fontPaths = [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Verdana.ttf",
            "/Library/Fonts/Arial.ttf",
            "C:/Windows/Fonts/arial.ttf",
            "C:/Windows/Fonts/segoeui.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
        ]
    }

    guard let path = fontPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
        preconditionFailure("No sample font was found. Install a system font or pass its path with --font.")
    }
    guard let font = CGFont(path) else {
        preconditionFailure("The sample font could not be loaded from \(path).")
    }
    return font
}
