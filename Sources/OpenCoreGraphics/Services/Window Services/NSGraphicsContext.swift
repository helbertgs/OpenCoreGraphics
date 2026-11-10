import Foundation

/// An object that represents a graphics context.
@MainActor open class NSGraphicsContext {

    // MARK: - Managing the Current Context

    /// Returns the current graphics context of the current thread.
    @MainActor public static var current: NSGraphicsContext? = nil

    /// The Core Graphics context, which is a low-level, platform-specific graphics context.
    public let cgContext: CGContext

    // MARK: - Creating a Graphics Context

    ///  Creates a new graphics context from the specified Core Graphics context and the initial flipped state.
    /// 
    /// - Parameters
    ///  - graphicsPort: The graphics port used to create the graphics-context object, as a CGContext (opaque type) object.
    ///  - initialFlippedState: Specifies the receiver’s initial flipped state. This is the value returned by isFlipped when no view has focus. 
    public init(cgContext graphicsPort: CGContext, initialFlippedState: Bool) {
        self.cgContext = graphicsPort
    }

    // MARK: - Managing the Graphics State

    /// This method must have been preceded with a ``saveGraphicsState()`` message to add the graphics state to the stack. Invocations of ``saveGraphicsState()`` and ``restoreGraphicsState()`` methods may be nested.
    /// 
    /// Restoring the graphics state restores such attributes as the current drawing style, transformation matrix, color, and font of the original graphics state.
    open func restoreGraphicsState() {
        cgContext.restoreGState()
    }

    /// The new graphics state is a copy of the previous state that can be modified to handle new drawing operations.
    /// 
    /// Saving the graphics state saves such attributes as the current drawing style, transformation matrix, color, and font. 
    /// To set drawing style attributes, use the methods of ``CGPath``. 
    /// Other attributes are accessed through appropriate objects such as CGAffineTransform, CGColor, and CGFont.
    public func saveGraphicsState() {
        cgContext.saveGState()
    }

    // MARK: - Testing the Drawing Destination

    /// A Boolean value that indicates whether the drawing destination is the screen.
    public var isDrawingToScreen: Bool = false

    // MARK: - Getting Information About the Context

    /// A Boolean value that indicates the graphics context’s flipped state.
    public var isFlipped: Bool = false

    // MARK: - Flushing Graphics to the Context
    
    /// Forces any buffered operations or data to be sent to the graphics context’s destination.
    public func flushGraphics() {
        cgContext.flush()
    }
}