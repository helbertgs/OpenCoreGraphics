/// Indicates that the current clip could not be rasterized for its destination dimensions.
enum CGClipCoverageError: Error, Equatable {
    /// Coverage generation failed because the destination or rasterization was invalid.
    case rasterizationFailed
}
