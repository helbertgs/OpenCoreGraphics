import Foundation
@preconcurrency import OpenGLAD
import OpenGLFW

extension CGWindow {
    func createWindow() {
        if glfwInit() == GLFW_FALSE {
            fatalError("Failed to initialize GLFW")
        }

        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE)

        guard let windowRef = glfwCreateWindow(Int32(frame.size.width), Int32(frame.size.height), title, nil, nil) else {
            fatalError("GLFW: Window not created!")
        }

        glfwMakeContextCurrent(windowRef)

        guard gladLoaderLoadGL() != GL_FALSE else {
            fatalError("GLAD: Fail to initialize")
        }

        self.windowRef = windowRef
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

    nonisolated func terminate() {
        glfwTerminate()
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
    }

    func clear() {
        let c = backgroundColor.components
        glad_glClearColor(c[0], c[1], c[2], c[3])
        glad_glClear(GLenum(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
    }

    private func setFramebufferSizeCallback() {
        guard let windowRef = self.windowRef else { return }
        glfwSetFramebufferSizeCallback(windowRef) { pointer, width, height in
            glad_glViewport(0, 0, width, height)
        }
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