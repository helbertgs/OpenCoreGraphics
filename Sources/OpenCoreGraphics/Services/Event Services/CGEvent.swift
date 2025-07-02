import Foundation

public typealias CGEventSourceKeyboardType = UInt32

/// Defines an opaque type that represents a low-level hardware event.
public class CGEvent {

    /// Creates a new event with the specified type.
    public init() {
    }

    public static func keyEvent(key: Int32, scanCode: Int32, action: Int32, mods: Int32) -> CGEvent {
        let event = CGEvent()
        event.type = action == 0 ? .keyUp : .keyDown
        event.keyCode = scanCode
        event.flags = CGEventFlags(rawValue: Int(mods))

        return event
    }

    public static func mouseEvent(button: Int32, action: Int32, mods: Int32) -> CGEvent {
        let event = CGEvent()
        event.mouseButton = button
        event.type = switch (button, action) {
        case (0, 0): .leftMouseUp
        case (0, 1): .leftMouseDown
        case (0, 2): .leftMouseDragged
        case (1, 0): .rightMouseUp
        case (1, 1): .rightMouseDown
        case (1, 2): .rightMouseDragged
        case (_, 0): .otherMouseUp
        case (_, 1): .otherMouseDown
        case (_, 2): .otherMouseDragged
        default: .none
        }

        return event
    }

    // MARK: - Getting the event type

    /// Returns the event type of a Core Graphics event (left mouse down, for example).
    public var type: CGEventType = .none

    // MARK: - Getting general event information

    /// Returns the location of a Core Graphics mouse event.
    public var location: CGPoint = .zero

    /// Returns the timestamp of a Core Graphics event.
    public var timestamp: CGEventTimestamp = 0

    /// The window object associated with the event.
    public weak var window: CGWindow?

    // MARK: - Getting modifier flags

    /// Returns the event flags of a Core Graphics event.
    public var flags: CGEventFlags?

    // MARK: - Getting key event information

    /// The virtual code for the key associated with the event.
    public var keyCode: CGKeyCode = 0

    // MARK: - Getting mouse event information

    public var mouseButton: CGMouseButton = 0
}

extension CGEvent {
    public enum CGEventType {
        
        /// Specifies a null event.
        case none

        /// Specifies a mouse down event with the left button.
        case leftMouseDown

        /// Specifies a mouse up event with the left button.
        case leftMouseUp

        /// Specifies a mouse down event with the right button.
        case rightMouseDown

        /// Specifies a mouse up event with the right button.
        case rightMouseUp

        /// Specifies a mouse moved event.
        case mouseMoved

        /// Specifies a mouse drag event with the left button down.
        case leftMouseDragged

        /// Specifies a mouse drag event with the right button down.
        case rightMouseDragged

        /// Specifies a key down event.
        case keyDown

        /// Specifies a key up event.
        case keyUp

        /// Specifies a key changed event for a modifier or status key.
        case flagsChanged

        /// Specifies a scroll wheel moved event.
        case scrollWheel

        /// Specifies a mouse down event with one of buttons 2-31.
        case otherMouseDown

        /// Specifies a mouse up event with one of buttons 2-31.
        case otherMouseUp

        /// Specifies a mouse drag event with one of buttons 2-31 down.
        case otherMouseDragged
    }
}

extension CGEvent {
    /// Constants that indicate the modifier key state at the time an event is created, as well as other event-related states.
    /// 
    /// These constants specify masks for the bits in an event flags bit mask. 
    /// Event flags indicate the modifier key state at the time an event is created, as well as other event-related states. 
    /// Event flags are used in accessor functions such as flags, CGEventSetFlags, and flagsState(_:).
    public struct CGEventFlags : OptionSet, Sendable, Hashable, RawRepresentable {

        // MARK: - Constants

        /// Indicates that the Caps Lock key is down for a keyboard, mouse, or flag-changed event.
        public static let maskAlphaShift = CGEventFlags(rawValue: 0x00010000)

        /// Indicates that the Shift key is down for a keyboard, mouse, or flag-changed event.
        public static let maskShift = CGEventFlags(rawValue: 0x00020000)

        /// Indicates that the Control key is down for a keyboard, mouse, or flag-changed event.
        public static let maskControl = CGEventFlags(rawValue: 0x00040000)

        /// Indicates that the Alt or Option key is down for a keyboard, mouse, or flag-changed event.
        public static let maskAlternate = CGEventFlags(rawValue: 0x00080000)

        /// Indicates that the Command key is down for a keyboard, mouse, or flag-changed event.
        public static let maskCommand = CGEventFlags(rawValue: 0x00100000)

        /// Indicates that the Help modifier key is down for a keyboard, mouse, or flag-changed event. This key is not present on most keyboards, and is different than the Help key found in the same row as Home and Page Up.
        public static let maskHelp = CGEventFlags(rawValue: 0x00400000)

        /// Indicates that the Fn (Function) key is down for a keyboard, mouse, or flag-changed event. This key is found primarily on laptop keyboards.
        public static let maskSecondaryFn = CGEventFlags(rawValue: 0x00800000)

        /// Identifies key events from the numeric keypad area on extended keyboards.
        public static let maskNumericPad = CGEventFlags(rawValue: 0x00400000)

        /// Indicates that mouse and pen movement events are not being coalesced.
        public static let maskNonCoalesced = CGEventFlags(rawValue: 0x00000100)

        // MARK: - Accessing the Raw Value
        
        /// The corresponding value of the raw type.
        public var rawValue: Int

        // MARK: - Creating a Value
        
        /// Creates a new instance with the specified raw value.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

extension CGEvent {
    /// Represents the number of buttons being set in a synthetic mouse event.
    public typealias CGButtonCount = Int32
}

extension CGEvent {
    /// Represents a character generated by pressing one or more keys on a keyboard.
    public typealias CGCharCode = UInt16
}

extension CGEvent {
    /// Defines the elapsed time in nanoseconds since startup that a Core Graphics event occurred.
    public typealias CGEventTimestamp = Double
}

extension CGEvent {
    /// A type that represents a key code for a keyboard event.
    public typealias CGKeyCode = Int32
}

extension CGEvent {
    /// A type that represents a mouse button for a mouse event.
    public typealias CGMouseButton = Int32
}