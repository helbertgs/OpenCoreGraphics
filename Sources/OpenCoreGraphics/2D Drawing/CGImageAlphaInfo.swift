import Foundation

/// Storage options for alpha component data.
public enum CGImageAlphaInfo : String, CaseIterable, Codable, Equatable, Hashable, Sendable {

    /// The alpha component is stored in the most significant bits of each pixel. For example, non-premultiplied ARGB.
    case first

    /// The alpha component is stored in the least significant bits of each pixel. For example, non-premultiplied RGBA.
    case last

    /// There is no alpha channel.
    case none

    /// There is no alpha channel. If the total size of the pixel is greater than the space required for the number of color components in the color space, the most significant bits are ignored.
    case noneSkipFirst

    /// There is no color data, only an alpha channel.
    case alphaOnly

    /// There is no alpha channel.
    case noneSkipLast

    /// The alpha component is stored in the most significant bits of each pixel and the color components have already been multiplied by this alpha value. For example, premultiplied ARGB.
    case premultipliedFirst

    /// The alpha component is stored in the least significant bits of each pixel and the color components have already been multiplied by this alpha value. For example, premultiplied RGBA.
    case premultipliedLast
}