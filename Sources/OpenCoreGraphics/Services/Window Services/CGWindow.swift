import Foundation
import OpenGLFW

/// A window that an app displays on the screen.
@MainActor 
open class CGWindow {

    // MARK: - Creating a Window 

    /// Creates a window with the specified frame.
    /// - Parameter frame: The frame of the window.
    /// - Returns: A new window.
    public init(frame: CGRect) {
        self.frame = frame
        createWindow()
    }

    deinit {
        terminate()
    }

    public var display: () -> Void = { }

    // MARK: - Instance Properties

    /// The GLFW window reference associated with the window.
    var windowRef: OpaquePointer?

    /// The OpenGL context associated with the window.
    public lazy var cgContext: CGContext = {
        let pixelsWide = Int(frame.size.width)
        let pixelsHgith = Int(frame.size.height)

        let bitmapBytesPerRow = pixelsWide * 4
        let bitmapByteCount = bitmapBytesPerRow * pixelsHgith
        let colorSpace = CGColorSpace.genericRGBLinear
        let bitmapData = UnsafeMutableRawPointer.allocate(byteCount: bitmapByteCount, alignment: 1)

        return .init(
            data: bitmapData,
            width: pixelsWide,
            height: pixelsHgith,
            bitsPerComponent: 8,
            bytesPerRow: bitmapBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }()

    // MARK: - Configuring the Window’s Appearance

    /// The color of the window’s background.
    public var backgroundColor: CGColor = .white

    /// The window’s color space.
    public var colorSpace: CGColorSpace?

    // MARK: - Accessing Window Information

    /// The window number of the window’s window device.
    var windowNumber: Int = -1

    // MARK: - Sizing Windows

    /// The window’s frame rectangle, which includes the title bar.
    public internal(set) var frame: CGRect

    /// A Boolean value that indicates whether the window is in a zoomed state.
    public private(set) var isZoomed: Bool = false

    /// This action method simulates the user clicking the zoom box by momentarily highlighting the button and then zooming the window.
    open func zoom(_ sender: Any?) {
    }

    // MARK: - Managing Window Visibility and Occlusion State

    /// A Boolean value that indicates whether the window is visible.
    public private(set) var isVisible: Bool = false

    // MARK: - Managing Key Status

    /// Moves the window to the front of the screen list, within its level, and makes it the key window; that is, it shows the window.
    /// - Parameter sender: The message’s sender.
    open func makeKeyAndOrderFront(_ sender: Any? = nil) {
        showWindow()

        while !shouldClose() {
            pollEvents()
            clear()
            displayIfNeeded()
            swapBuffers()
        }
    }

    // MARK: - Drawing Windows

    /// Passes a display message down the window’s view hierarchy, thus redrawing all views within the window.
    // open func display() {
    // }

    /// Passes a display message down the window’s view hierarchy, thus redrawing all views that need displaying.
    open func displayIfNeeded() {
        if viewsNeedDisplay {
            display()
        }
    }

    /// A Boolean value that indicates whether any of the window’s views need to be displayed.
    open var viewsNeedDisplay: Bool = true

    // MARK: - Updating Windows

    /// Updates the window.
    open func update() {
    }

    // MARK: - Converting Coordinates

    // MARK: - Managing Titles

    /// The string that appears in the title bar of the window.
    public var title: String {
        get { 
            if let windowRef {
                return String(cString: glfwGetWindowTitle(windowRef))
            }
            return ""
        }
        set { glfwSetWindowTitle(windowRef, newValue) }
    }

    // MARK: - Accessing Screen Information

    /// The screen the window is on.
    public var screen: Any?

    // MARK: - Moving Windows

    /// Sets the window’s location to the center of the screen.
    public func center() {
    }

    // MARK: - Minimizing Windows

    /// Removes the window from the screen list and displays the minimized window in the Dock.
    open func miniaturize(_ sender: Any? = nil) {
    }

    /// De-minimizes the window.
    open func deminiaturize(_ sender: Any? = nil) {
    }

    // MARK: - Handling Events

    open func sendEvent(_ event: CGEvent) {
    }
}