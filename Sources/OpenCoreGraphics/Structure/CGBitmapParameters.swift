import Foundation

@dynamicMemberLookup
public struct CGBitmapParameters {
    public var colorSpace: CGColorSpace
    private var property: [String: Any] = [:]

    init(colorSpace: CGColorSpace = .sRGB) {
        self.colorSpace = colorSpace
    }

    public subscript<T>(dynamicMember member: String) -> T {
        get { return property[member] as! T }
        set { property[member] = newValue }
    }
}