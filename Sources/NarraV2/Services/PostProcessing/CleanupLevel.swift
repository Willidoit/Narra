import Foundation

public enum CleanupLevel: String, Sendable, CaseIterable, Codable {
    case none
    case light
    case medium
    case high
}
