import Foundation

/// Junction types for stroked lines.
/// 
/// A line join specifies how ``strokePath()`` draws the junction between connected line segments. 
/// To set the line join style in a graphics context, you use the function ``setLineJoin(_:)``.
public enum CGLineJoin : String, Codable, Equatable, Hashable, Sendable {

    case miter
    
    /// A join with a rounded end. 
    /// 
    /// OpenCoreGraphics draws the line to extend beyond the endpoint of the path. 
    /// The line ends with a semicircular arc with a radius of 1/2 the line’s width, centered on the endpoint.
    case round
    
    /// A join with a squared-off end. 
    /// 
    /// OpenCoreGraphics draws the line to extend beyond the endpoint of the path, for a distance of 1/2 the line’s width.
    case bevel
}