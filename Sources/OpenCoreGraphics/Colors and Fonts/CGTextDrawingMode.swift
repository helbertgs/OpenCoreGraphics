import Foundation

/// Modes for rendering text.
/// 
/// You provide a text drawing mode constant to the function ``setTextDrawingMode(_:)`` to set the current text drawing mode for a graphics context. 
/// Text drawing modes determine how Core Graphics renders individual glyphs onscreen. 
/// For example, you can set a text drawing mode to draw text filled in or outlined (stroked) or both. 
/// You can also create special effects with the text clipping drawing modes, such as clipping an image to a glyph shape.
@frozen public enum CGTextDrawingMode : String, Codable, Equatable, Hashable, Sendable {

    /// Perform a fill operation on the text.
    case fill

    /// Perform a stroke operation on the text.
    case stroke

    /// Perform fill, then stroke operations on the text.
    case fillStroke

    /// Do not draw the text, but do update the text position.
    case invisible

    /// Perform a fill operation, then intersect the text with the current clipping path.
    case fillClip

    /// Perform a stroke operation, then intersect the text with the current clipping path.
    case strokeClip

    /// Perform fill then stroke operations, then intersect the text with the current clipping path.
    case fillStrokeClip

    /// Specifies to intersect the text with the current clipping path. This mode does not paint the text.
    case clip
}