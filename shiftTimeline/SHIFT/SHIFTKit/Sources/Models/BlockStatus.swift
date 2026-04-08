import Foundation

public enum BlockStatus: String, Codable, CaseIterable, Sendable {
    case upcoming
    case active
    case overtime
    case completed
}
