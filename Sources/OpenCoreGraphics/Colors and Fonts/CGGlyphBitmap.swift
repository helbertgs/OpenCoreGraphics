import Foundation

/// An 8-bit coverage bitmap and its offset from a glyph's text-space origin.
struct CGGlyphBitmap: Equatable, Sendable {
    /// The bitmap width in pixels.
    let width: Int

    /// The bitmap height in pixels.
    let height: Int

    /// The horizontal offset from the glyph origin.
    let xOffset: Int

    /// The vertical offset from the baseline.
    let yOffset: Int

    /// The row-major coverage values, where zero is transparent and 255 is opaque.
    let coverage: Data
}
