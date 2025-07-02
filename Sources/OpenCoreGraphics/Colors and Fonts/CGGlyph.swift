import Foundation

/// An index into the internal glyph table of a font.
/// 
/// When drawing text, you typically specify a sequence of characters. 
/// However, Core Graphics also allows you to use CGGlyph values to specify glyphs. 
/// In either case, Core Graphics renders the text using font data provided by the Apple Type Services (ATS) framework.
/// 
/// You provide CGGlyph values to the functions ``showGlyphs(g:count:)`` and`` showGlyphsAtPoint(x:y:glyphs:count:)``. 
/// These functions display an array of glyphs at the current text position or at a position you specify, respectively.
public typealias CGGlyph = UInt16