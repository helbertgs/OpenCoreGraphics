import Foundation

public enum CGComponent : String, Codable, Equatable, Hashable, Sendable {
    case float16Bit
    case float32Bit
    case integer10Bit
    case integer16Bit
    case integer32Bit
    case integer8Bit
    case unknown
}