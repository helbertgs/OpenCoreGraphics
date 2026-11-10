import Foundation
import OpenCoreGraphics

let window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 512, height: 512), title: "OpenCoreGraphics Sample")

window.display = {
    let cgContext = window.cgContext

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

    cgContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    cgContext.fill(CGRect(x: 20, y: 20, width: 150, height: 200))

    cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    cgContext.fill(CGRect(x: 200, y: 100, width: 150, height: 200))
}

window.makeKeyAndOrderFront()
