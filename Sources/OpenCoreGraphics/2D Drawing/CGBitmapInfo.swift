import Foundation

/// Component information for a bitmap image.
/// 
/// Applications that store pixel data in memory using ARGB format must take care in how they read data. 
/// If the code is not written correctly, it’s possible to misread the data which leads to colors or alpha that appear wrong. 
/// The byte order constants specify the byte ordering of pixel formats. 
/// To specify byte ordering, use a bitwise OR operator to combine the appropriate constant with the bitmapInfo parameter.
public struct CGBitmapInfo : Equatable, OptionSet, Sendable {
    
    // MARK: - Constants

    /// The alpha information mask. Use this to extract alpha information that specifies whether a bitmap contains an alpha channel and how the alpha channel is generated.
    public static let alphaInfoMask =  CGBitmapInfo(rawValue: 1 << 1)

    /// The components of a bitmap are floating-point values.
    public static let floatComponents =  CGBitmapInfo(rawValue: 1 << 2)

    /// The byte ordering of pixel formats.
    public static let byteOrderMask =  CGBitmapInfo(rawValue: 1 << 4)

    /// The default byte order.
    public static let byteOrderDefault =  CGBitmapInfo(rawValue: 1 << 8)

    /// 16-bit, little endian format.
    public static let byteOrder16Little =  CGBitmapInfo(rawValue: 1 << 16)

    /// 32-bit, little endian format.
    public static let byteOrder32Little =  CGBitmapInfo(rawValue: 1 << 32)

    /// 16-bit, big endian format.
    public static let byteOrder16Big =  CGBitmapInfo(rawValue: 1 << 64)

    /// 32-bit, big endian format.
    public static let byteOrder32Big =  CGBitmapInfo(rawValue: 1 << 128)


    public static let floatInfoMask =  CGBitmapInfo(rawValue: 1 << 256)

    // MARK: - Accessing the Raw Value
    
    /// The corresponding value of the raw type.
    public let rawValue: Int

    // MARK: - Creating a Value

    /// Creates a new instance with the specified raw value.
    /// - Parameter rawValue: The raw value to use for the new instance.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}