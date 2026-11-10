import Foundation
import OpenGLFW
@preconcurrency import OpenGLAD

/// A window that an app displays on the screen.
@MainActor 
open class CGWindow {

    // MARK: - Creating a Window 

    /// Creates a window with the specified frame and title.
    /// - Parameter frame: The frame of the window.
    /// - Parameter title: The string displayed in the window title bar.
    /// - Returns: A new window.
    /// - Throws: A ``CGWindowError`` when GLFW or OpenGL initialization fails.
    public init(frame: CGRect, title: String = "") throws {
        self.frame = frame
        storedTitle = title
        try createWindow()
        do {
            let renderer = try GLRenderer()
            self.renderer = renderer
            windowRenderTarget = WindowRenderTarget(size: framebufferSize, renderer: renderer)
        } catch {
            destroy()
            throw error
        }
    }

    /// Releases the window's GLFW reference when it is deallocated.
    isolated deinit {
        renderer = nil
        destroy()
    }

    public var display: () -> Void = { }

    // MARK: - Instance Properties

    /// The GLFW window reference associated with the window.
    var windowRef: OpaquePointer?

    /// The title to use before a GLFW window reference exists.
    private var storedTitle = ""

    /// Indicates whether this window owns a GLFW platform reference.
    private var hasRetainedPlatform = false

    /// The OpenGL renderer owned by this window.
    private var renderer: GLRenderer?

    /// The render target shared with the window's drawing context.
    private var windowRenderTarget: WindowRenderTarget?

    /// The current framebuffer dimensions in pixels.
    private var framebufferSize: CGSize = .zero

    /// Tracks whether the lazily created context needs framebuffer-size updates.
    private var hasCreatedCGContext = false

    /// The OpenGL context associated with the window.
    public lazy var cgContext: CGContext = {
        let context = CGContext(width: Int(framebufferSize.width), height: Int(framebufferSize.height))
        context.renderTarget = windowRenderTarget
        hasCreatedCGContext = true
        return context
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

    /// Passes a display message down the window’s view hierarchy, thus redrawing all views that need displaying.
    open func displayIfNeeded() {
        if viewsNeedDisplay {
            display()
            cgContext.flush()
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
            return storedTitle
        }
        set {
            storedTitle = newValue
            if let windowRef {
                glfwSetWindowTitle(windowRef, newValue)
            }
        }
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

extension CGWindow {
    func createWindow() throws {
        guard GLFWPlatform.shared.retain() else {
            throw CGWindowError.glfwInitFailed
        }
        hasRetainedPlatform = true

        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
        glfwWindowHint(GLFW_STENCIL_BITS, 8)
        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE)

        guard let windowRef = glfwCreateWindow(Int32(frame.size.width), Int32(frame.size.height), storedTitle, nil, nil) else {
            destroy()
            throw CGWindowError.windowCreationFailed
        }

        self.windowRef = windowRef
        glfwMakeContextCurrent(windowRef)

        guard gladLoaderLoadGL() != GL_FALSE else {
            glfwMakeContextCurrent(nil)
            destroy()
            throw CGWindowError.gladLoadFailed
        }

        var framebufferWidth: Int32 = 0
        var framebufferHeight: Int32 = 0
        glfwGetFramebufferSize(windowRef, &framebufferWidth, &framebufferHeight)
        updateFramebufferSize(width: framebufferWidth, height: framebufferHeight)

        setupCallbacks()
    }

    func setupCallbacks() {
        setupUserPointer()
        setFramebufferSizeCallback()
        setKeyboardCallback()
        setMouseCallback()
        setWindowResizeCallback()
    }

    func setupUserPointer() {
        guard let windowRef = self.windowRef else { return }
        glfwSetWindowUserPointer(windowRef, Unmanaged.passUnretained(self).toOpaque())
    }

    func shouldClose() -> Bool {
        guard let windowRef = self.windowRef else { return false }
        return glfwWindowShouldClose(windowRef) == GLFW_TRUE
    }

    func setShouldClose(_ shouldClose: Bool) {
        guard let windowRef = self.windowRef else { return }
        glfwSetWindowShouldClose(windowRef, shouldClose ? GLFW_TRUE : GLFW_FALSE)
    }

    func swapBuffers() {
        guard let windowRef = self.windowRef else { return }
        glfwSwapBuffers(windowRef)
    }

    func pollEvents() {
        glfwPollEvents()
    }

    func swapInterval(_ interval: Int) {
        glfwSwapInterval(Int32(interval))
    }
    
    func waitEvents() {
        glfwWaitEvents()
    }

    func showWindow() {
        guard let windowRef = self.windowRef else { return }
        glfwShowWindow(windowRef)
    }

    func destroy() {
        if let windowRef = self.windowRef {
            glfwDestroyWindow(windowRef)
        }

        windowRef = nil
        if hasRetainedPlatform {
            hasRetainedPlatform = false
            GLFWPlatform.shared.release()
        }
    }

    func clear() {
        let c = backgroundColor.components
        glad_glClearColor(Float(c[0]), Float(c[1]), Float(c[2]), Float(c[3]))
        glad_glClear(GLenum(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
    }

    private func setFramebufferSizeCallback() {
        guard let windowRef = self.windowRef else { return }
        glfwSetFramebufferSizeCallback(windowRef) { pointer, width, height in
            let window: CGWindow = Unmanaged<CGWindow>.fromOpaque(glfwGetWindowUserPointer(pointer)).takeUnretainedValue()
            window.updateFramebufferSize(width: width, height: height)
        }
    }

    private func updateFramebufferSize(width: Int32, height: Int32) {
        let size = CGSize(width: width, height: height)
        framebufferSize = size
        glad_glViewport(0, 0, width, height)
        windowRenderTarget?.size = size

        guard hasCreatedCGContext else { return }
        cgContext.width = Int(width)
        cgContext.height = Int(height)
    }

    private func setKeyboardCallback() {
        guard let windowRef = self.windowRef else { return }
        glfwSetKeyCallback(windowRef) { (windowRef, key, scancode, action, mods) in
            let window: CGWindow = Unmanaged<CGWindow>.fromOpaque(glfwGetWindowUserPointer(windowRef)).takeUnretainedValue()
            let event = CGEvent.keyEvent(key: key, scanCode: scancode, action: action, mods: mods)
            event.window = window
            event.timestamp = glfwGetTime()
            window.sendEvent(event)
        }
    }

    private func setMouseCallback() {
        guard let windowRef = self.windowRef else { return }
        glfwSetCursorPosCallback(windowRef) { (windowRef, xpos, ypos) in
            let window: CGWindow = Unmanaged<CGWindow>.fromOpaque(glfwGetWindowUserPointer(windowRef)).takeUnretainedValue()
            let event = CGEvent()
            event.type = .mouseMoved
            event.location = CGPoint(x: xpos, y: ypos)
            event.window = window
            event.timestamp = glfwGetTime()
            window.sendEvent(event)
        }

        glfwSetMouseButtonCallback(windowRef) { (windowRef, button, action, mods) in
            let window: CGWindow = Unmanaged<CGWindow>.fromOpaque(glfwGetWindowUserPointer(windowRef)).takeUnretainedValue()
            let event = CGEvent.mouseEvent(button: button, action: action, mods: mods)
            event.timestamp = glfwGetTime()
            event.window = window
            window.sendEvent(event)
        }
    }

    private func setWindowResizeCallback() {
        guard let windowRef = self.windowRef else { return }
        glfwSetWindowSizeCallback(windowRef) { (windowRef, width, height) in
            let window: CGWindow = Unmanaged<CGWindow>.fromOpaque(glfwGetWindowUserPointer(windowRef)).takeUnretainedValue()
            window.frame = .init(origin: window.frame.origin, size: CGSize(width: width, height: height))
        }
    }
}