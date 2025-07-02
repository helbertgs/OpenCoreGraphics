import Foundation

/// Handling options for colors that are not located within the destination color space of a graphics context.
public enum CGColorRenderingIntent : Equatable, Hashable, Sendable {
    case defaultIntent
    case absoluteColorimetric
    case relativeColorimetric
    case perceptual
    case saturation
}