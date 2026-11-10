import Foundation

/// Modes for rendering text.
/// 
/// You provide a text drawing mode constant to the function ``setTextDrawingMode(_:)`` to set the current text drawing mode for a graphics context. 
/// Text drawing modes determine how Core Graphics renders individual glyphs onscreen. 
/// For example, you can set a text drawing mode to draw text filled in or outlined (stroked) or both. 
/// You can also create special effects with the text clipping drawing modes, such as clipping an image to a glyph shape.
public enum CGTextDrawingMode : String, Codable, Equatable, Hashable, Sendable {

    /// Perform a fill operation on the text.
    case fill

    /// Perform a stroke operation on the text.
    /// Software text rendering does not support strokes yet and treats this as `fill`.
    case stroke

    /// Perform fill, then stroke operations on the text.
    /// Software text rendering does not support strokes yet and treats this as `fill`.
    case fillStroke

    /// Requests invisible text and updates the text position.
    /// This mode is not supported by software text rendering and is treated as `fill`.
    case invisible

    /// Perform a fill operation, then intersect the text with the current clipping path.
    /// Text clipping is not supported yet and this mode is treated as `fill`.
    case fillClip

    /// Perform a stroke operation, then intersect the text with the current clipping path.
    /// Stroke and text clipping are not supported yet and this mode is treated as `fill`.
    case strokeClip

    /// Perform fill then stroke operations, then intersect the text with the current clipping path.
    /// Stroke and text clipping are not supported yet and this mode is treated as `fill`.
    case fillStrokeClip

    /// Specifies to intersect the text with the current clipping path. This mode does not paint the text.
    /// Text clipping is not supported yet and this mode is treated as `fill`.
    case clip
}