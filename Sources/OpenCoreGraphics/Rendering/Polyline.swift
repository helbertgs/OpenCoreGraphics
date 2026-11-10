/// A connected sequence of points that represents one flattened path subpath.
struct Polyline: Equatable, Sendable {
    /// The points that define the line segments in this subpath.
    let points: [CGPoint]

    /// Whether the last point connects back to the first point.
    let isClosed: Bool
}
