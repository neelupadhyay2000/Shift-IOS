import Foundation

/// Data shared between the main app and the iOS home screen widget
/// via the App Group UserDefaults suite.
public struct WidgetSharedData: Codable, Sendable {
    /// Title of the currently active block (e.g. "Ceremony").
    public let activeBlockTitle: String
    /// The scheduled end time of the active block — used by the widget
    /// `Text(date, style: .timer)` for a live-counting countdown.
    public let blockEndDate: Date
    /// Title of the next upcoming block, if any.
    public let nextBlockTitle: String?
    /// Sunset time for the event day, if available.
    public let sunsetTime: Date?
    /// The live event's UUID — used for deep-link tap target.
    public let eventID: UUID
    /// Human-readable event name shown in the medium widget.
    public let eventName: String
    /// Whether the event is currently live. When `false`, widgets
    /// show a "No Active Event" placeholder.
    public let isEventLive: Bool

    public init(
        activeBlockTitle: String,
        blockEndDate: Date,
        nextBlockTitle: String? = nil,
        sunsetTime: Date? = nil,
        eventID: UUID,
        eventName: String,
        isEventLive: Bool
    ) {
        self.activeBlockTitle = activeBlockTitle
        self.blockEndDate = blockEndDate
        self.nextBlockTitle = nextBlockTitle
        self.sunsetTime = sunsetTime
        self.eventID = eventID
        self.eventName = eventName
        self.isEventLive = isEventLive
    }
}

/// Reads and writes ``WidgetSharedData`` to the shared App Group
/// `UserDefaults` suite so the widget extension can display live
/// timeline data without accessing SwiftData directly.
public enum WidgetDataStore {
    public static let suiteName = "group.com.neelsoftwaresolutions.shiftTimeline"
    private static let dataKey = "widgetSharedData"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// Writes fresh data for the widget to read on its next timeline reload.
    public static func save(_ data: WidgetSharedData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        defaults?.set(encoded, forKey: dataKey)
    }

    /// Reads the last-saved widget data. Returns `nil` if no live event
    /// has ever been written.
    public static func load() -> WidgetSharedData? {
        guard let data = defaults?.data(forKey: dataKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSharedData.self, from: data)
    }

    /// Clears widget data (e.g. when exiting live mode or event completes).
    public static func clear() {
        defaults?.removeObject(forKey: dataKey)
    }
}
