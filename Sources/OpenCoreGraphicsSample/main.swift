import OpenCoreGraphics

let window = CGWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 450))
window.title = "OpenCoreGraphics Sample"

window.display = {
    window.cgContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    window.cgContext.fill(CGRect(x: 20, y: 20, width: 150, height: 200))

    window.cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    window.cgContext.fill(CGRect(x: 200, y: 100, width: 150, height: 200))

    window.cgContext.draw(CGImage(url: "/Users/helbert.gomes/Downloads/Photo.jpg"), in: CGRect(x: 352, y: 123.6, width: 196, height: 202.8))
}

window.makeKeyAndOrderFront()