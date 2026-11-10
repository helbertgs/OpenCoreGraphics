import Foundation

/// Styles for rendering the endpoint of a stroked line.
///
/// A line cap specifies the method used by ``strokePath()`` to draw the endpoint of the line. 
/// To change the line cap style in a graphics context, you use the function ``setLineCap(_:)``.
public enum CGLineCap: String, Codable, Equatable, Hashable, Sendable {
    
    /// A line with a squared-off end.
    /// 
    /// OpenCoreGraphics draws the line to extend only to the exact endpoint of the path. 
    /// This is the default.
    case butt

    /// A line with a rounded end.
    /// 
    /// OpenCoreGraphics draws the line to extend beyond the endpoint of the path. 
    /// The line ends with a semicircular arc with a radius of 1/2 the line’s width, centered on the endpoint.
    case round

    /// A line with a squared-off end.
    ///
    /// OpenCoreGraphics extends the line beyond the endpoint of the path for a distance equal to half the line width.
    case square
}