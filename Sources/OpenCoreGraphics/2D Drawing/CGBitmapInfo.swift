import Foundation

/// Component information for a bitmap image.
/// 
/// Applications that store pixel data in memory using ARGB format must take care in how they read data. 
/// If the code is not written correctly, it’s possible to misread the data which leads to colors or alpha that appear wrong. 
/// The byte order constants specify the byte ordering of pixel formats. 
/// To specify byte ordering, use a bitwise OR operator to combine the appropriate constant with the bitmapInfo parameter.
public enum CGBitmapInfo : Int, Codable, Equatable, Hashable, Sendable {
    
    // MARK: - Constants

    /// The alpha information mask. Use this to extract alpha information that specifies whether a bitmap contains an alpha channel and how the alpha channel is generated.
    case alphaInfoMask = 1

    /// The components of a bitmap are floating-point values.
    case floatComponents =  2

    /// The byte ordering of pixel formats.
    case byteOrderMask = 4

    /// The default byte order.
    case byteOrderDefault = 8

    /// 16-bit, little endian format.
    case byteOrder16Little = 16

    /// 32-bit, little endian format.
    case byteOrder32Little = 32

    /// 16-bit, big endian format.
    case byteOrder16Big = 64

    /// 32-bit, big endian format.
    case byteOrder32Big = 128

    case floatInfoMask = 256

    public init(rawValue: Int) {
        switch rawValue {
            case 1: self = .alphaInfoMask
            case 2: self = .floatComponents
            case 4: self = .byteOrderMask
            case 8: self = .byteOrderDefault
            case 16: self = .byteOrder16Little
            case 32: self = .byteOrder32Little
            case 64: self = .byteOrder16Big
            case 128: self = .byteOrder32Big
            case 256: self = .floatInfoMask
            default: self = .byteOrderDefault
        
        }
    }
}