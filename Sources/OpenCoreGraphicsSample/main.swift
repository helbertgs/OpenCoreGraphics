import OpenCoreGraphics

let window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 512, height: 512), title: "OpenCoreGraphics Sample")

window.display = {
    let cgContext = window.cgContext

    cgContext.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    cgContext.fill(CGRect(x: 20, y: 20, width: 150, height: 200))

    cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    cgContext.fill(CGRect(x: 200, y: 100, width: 150, height: 200))
}

window.makeKeyAndOrderFront()
