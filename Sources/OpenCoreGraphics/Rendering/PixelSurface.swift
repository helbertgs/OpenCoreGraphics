import Foundation

/// A four-byte-per-pixel bitmap surface backed by owned or borrowed memory.
struct PixelSurface {
    /// One pixel expressed in red, green, blue, and alpha byte order.
    ///
    /// RGB values are raw storage values, so callers should premultiply them
    /// by alpha when writing to a premultiplied surface.
    struct Pixel: Equatable, Sendable {
        /// The red component, stored as an 8-bit value.
        let red: UInt8

        /// The green component, stored as an 8-bit value.
        let green: UInt8

        /// The blue component, stored as an 8-bit value.
        let blue: UInt8

        /// The alpha component, stored as an 8-bit value.
        let alpha: UInt8
    }

    /// The width of the surface in pixels.
    let width: Int

    /// The height of the surface in pixels.
    let height: Int

    /// The byte distance between the starts of adjacent rows.
    let bytesPerRow: Int

    /// The total number of bytes occupied by all rows.
    var byteCount: Int {
        bytesPerRow * height
    }

    /// The supported channel order of the surface's storage.
    private let channelOrder: ChannelOrder

    /// Whether the fourth storage byte represents alpha instead of padding.
    private let storesAlpha: Bool

    /// Keeps internally allocated memory alive for the lifetime of this value.
    private let ownedStorage: OwnedPixelStorage?

    /// The first byte of pixel storage.
    let dataPointer: UnsafeMutableRawPointer

    /// Creates a surface over caller-owned memory or a new zeroed allocation.
    /// - Parameters:
    ///   - data: The caller's pixel buffer, or nil to allocate owned memory.
    ///   - width: The number of pixels in each row.
    ///   - height: The number of rows in the surface.
    ///   - bytesPerRow: The byte distance between row starts, including padding.
    ///   - colorSpace: The color space used to interpret the RGB components.
    ///   - alphaInfo: The alpha layout used by each pixel.
    ///   - bitmapInfo: The byte order used by each pixel.
    /// - Returns: A surface when dimensions, row size, color space, and format are supported.
    init?(
        data: UnsafeMutableRawPointer?,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        colorSpace: CGColorSpace,
        alphaInfo: CGImageAlphaInfo,
        bitmapInfo: CGBitmapInfo
    ) {
        guard width > 0,
              height > 0,
              colorSpace.model == .rgb,
              let channelOrder = ChannelOrder(alphaInfo: alphaInfo, bitmapInfo: bitmapInfo) else {
            return nil
        }

        let (minimumBytesPerRow, rowSizeOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, allocationSizeOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard rowSizeOverflow == false,
              allocationSizeOverflow == false,
              bytesPerRow >= minimumBytesPerRow else {
            return nil
        }

        let ownedStorage: OwnedPixelStorage?
        let dataPointer: UnsafeMutableRawPointer
        if let data {
            ownedStorage = nil
            dataPointer = data
        } else {
            guard let storage = OwnedPixelStorage(byteCount: byteCount) else { return nil }
            ownedStorage = storage
            dataPointer = storage.pointer
        }

        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.channelOrder = channelOrder
        self.storesAlpha = alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
        self.ownedStorage = ownedStorage
        self.dataPointer = dataPointer
    }

    /// Reads a pixel as RGBA bytes, regardless of the surface's storage order.
    /// - Parameters:
    ///   - x: The zero-based column of the requested pixel.
    ///   - y: The zero-based row of the requested pixel.
    /// - Returns: The pixel in RGBA order, or nil when the coordinates are outside the surface.
    func pixel(x: Int, y: Int) -> Pixel? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = y * bytesPerRow + x * 4
        let bytes = dataPointer.assumingMemoryBound(to: UInt8.self)
        let alpha = storesAlpha ? bytes[offset + 3] : 255

        switch channelOrder {
        case .rgba:
            return Pixel(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: alpha
            )
        case .bgra:
            return Pixel(
                red: bytes[offset + 2],
                green: bytes[offset + 1],
                blue: bytes[offset],
                alpha: alpha
            )
        }
    }

    /// Writes a pixel using the surface's native channel order.
    /// - Parameters:
    ///   - pixel: The RGBA pixel to store.
    ///   - x: The zero-based column of the destination pixel.
    ///   - y: The zero-based row of the destination pixel.
    /// - Returns: True when the pixel was written; false when the coordinates are outside the surface.
    @discardableResult
    func setPixel(_ pixel: Pixel, x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        let offset = y * bytesPerRow + x * 4
        let bytes = dataPointer.assumingMemoryBound(to: UInt8.self)
        switch channelOrder {
        case .rgba:
            bytes[offset] = pixel.red
            bytes[offset + 1] = pixel.green
            bytes[offset + 2] = pixel.blue
        case .bgra:
            bytes[offset] = pixel.blue
            bytes[offset + 1] = pixel.green
            bytes[offset + 2] = pixel.red
        }
        bytes[offset + 3] = storesAlpha ? pixel.alpha : 255
        return true
    }
}

/// Releases memory allocated by a pixel surface when its last value copy goes away.
private final class OwnedPixelStorage {
    /// The raw allocation shared by copies of the owning surface.
    let pointer: UnsafeMutableRawPointer

    /// Allocates and zero-initializes the requested number of bytes.
    /// - Parameter byteCount: The number of bytes to allocate.
    /// - Returns: An allocation, or nil when the requested size is invalid.
    init?(byteCount: Int) {
        guard byteCount > 0 else { return nil }
        pointer = .allocate(byteCount: byteCount, alignment: MemoryLayout<UInt32>.alignment)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    }

    /// Releases the owned allocation.
    deinit {
        pointer.deallocate()
    }
}

/// Describes how color channels are arranged in each pixel.
private enum ChannelOrder {
    /// Red, green, blue, then alpha or padding.
    case rgba

    /// Blue, green, red, then alpha or padding.
    case bgra

    /// Resolves a supported four-byte bitmap layout.
    /// - Parameters:
    ///   - alphaInfo: The alpha channel position and presence.
    ///   - bitmapInfo: The byte order of the pixel.
    /// - Returns: The channel order, or nil when the pair is unsupported.
    init?(alphaInfo: CGImageAlphaInfo, bitmapInfo: CGBitmapInfo) {
        switch (alphaInfo, bitmapInfo) {
        case (.premultipliedLast, .byteOrderDefault),
             (.premultipliedLast, .byteOrder32Big),
             (.noneSkipLast, .byteOrderDefault),
             (.noneSkipLast, .byteOrder32Big):
            self = .rgba
        case (.premultipliedFirst, .byteOrder32Little),
             (.noneSkipFirst, .byteOrder32Little):
            self = .bgra
        default:
            return nil
        }
    }
}
