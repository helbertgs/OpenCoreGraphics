import Foundation

/// Storage options for alpha component data.
public enum CGImageAlphaInfo : Int, Codable, Equatable, Hashable, Sendable {

    /// The alpha component is stored in the most significant bits of each pixel. For example, non-premultiplied ARGB.
    case first = 4

    /// The alpha component is stored in the least significant bits of each pixel. For example, non-premultiplied RGBA.
    case last = 3

    /// There is no alpha channel.
    case none = 0

    /// There is no alpha channel. If the total size of the pixel is greater than the space required for the number of color components in the color space, the most significant bits are ignored.
    case noneSkipFirst = 6

    /// There is no color data, only an alpha channel.
    case alphaOnly = 7

    /// There is no alpha channel.
    case noneSkipLast = 5

    /// The alpha component is stored in the most significant bits of each pixel and the color components have already been multiplied by this alpha value. For example, premultiplied ARGB.
    case premultipliedFirst = 2

    /// The alpha component is stored in the least significant bits of each pixel and the color components have already been multiplied by this alpha value. For example, premultiplied RGBA.
    case premultipliedLast = 1
}