import Foundation

/// An offscreen context for reusing content drawn with Core Graphics.
public class CGLayer {

    // MARK: - Creating Layer Objects

    /// Creates a layer object that is associated with a graphics context.
    /// 
    /// After you create a ``CGLayer`` object, you should reuse it whenever you can to facilitate the Core Graphics caching strategy. 
    /// Core Graphics caches any objects that are reused, including ``CGLayer`` objects. 
    /// Objects that are reused frequently remain in the cache. 
    /// In contrast, objects that are used once in a while may be moved in and out of the cache according to their frequency of use. 
    /// If you don’t reuse ``CGLayer`` objects, Core Graphics won’t cache them. 
    /// This means that you lose an opportunity to improve the performance of your application.
    /// - Parameters:
    ///   - context: The graphics context you want to create the layer relative to.
    ///   - size: The size, in default user space units, of the layer relative to the graphics context.
    public init?(_ context: CGContext, size: CGSize) {
        self.context = context
        self.size = size
    }

    // MARK: - Examining a Layer

    /// Returns the graphics context associated with a layer object.
    public let context: CGContext?

    /// Returns the width and height of a layer object.
    public let size: CGSize
}