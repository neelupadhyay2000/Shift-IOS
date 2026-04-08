import Foundation

public enum EventStatus: String, Codable, CaseIterable, Sendable {
    case planning
    case live
    case completed
}
