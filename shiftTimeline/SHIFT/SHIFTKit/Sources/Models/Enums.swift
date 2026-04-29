import Foundation

public enum EventStatus: String, Codable, CaseIterable, Sendable {
    case planning
    case live
    case completed
}

public enum BlockStatus: String, Codable, CaseIterable, Sendable {
    case upcoming
    case active
    case overtime
    case completed
}

public enum VendorRole: String, Codable, CaseIterable, Sendable {
    case photographer
    case dj
    case planner
    case caterer
    case florist
    case custom
}

public enum ShiftSource: String, Codable, CaseIterable, Sendable {
    case manual
    case dependency
    case undo
    case watch
}

public enum BlockColor: String, Codable, CaseIterable, Sendable {
    case blue
    case red
    case green
    case orange
    case purple
    case pink
    case yellow
    case gray
}

public enum BlockIcon: String, Codable, CaseIterable, Sendable {
    case ceremony
    case dinner
    case music
    case photo
    case speech
    case travel
    case setup
    case custom
}
