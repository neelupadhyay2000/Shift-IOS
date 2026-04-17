import Foundation

/// Data contract sent from iPhone → Watch via `updateApplicationContext`.
///
/// Contains everything the Watch dashboard needs to render: the active block
/// countdown, the next block preview, sunset time, and live status.
/// Encoded/decoded as `[String: Any]` for WCSession compatibility.
public struct WatchContext: Codable, Sendable, Equatable {
    public let eventID: UUID
    public let eventTitle: String
    public let activeBlockTitle: String
    public let activeBlockEndTime: Date
    public let nextBlockTitle: String?
    public let nextBlockStartTime: Date?
    public let sunsetTime: Date?
    public let isLive: Bool

    public init(
        eventID: UUID,
        eventTitle: String,
        activeBlockTitle: String,
        activeBlockEndTime: Date,
        nextBlockTitle: String? = nil,
        nextBlockStartTime: Date? = nil,
        sunsetTime: Date? = nil,
        isLive: Bool
    ) {
        self.eventID = eventID
        self.eventTitle = eventTitle
        self.activeBlockTitle = activeBlockTitle
        self.activeBlockEndTime = activeBlockEndTime
        self.nextBlockTitle = nextBlockTitle
        self.nextBlockStartTime = nextBlockStartTime
        self.sunsetTime = sunsetTime
        self.isLive = isLive
    }

    // MARK: - WCSession Dictionary Encoding

    /// Encodes to a `[String: Any]` dictionary suitable for
    /// `WCSession.updateApplicationContext(_:)`.
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventID": eventID.uuidString,
            "eventTitle": eventTitle,
            "activeBlockTitle": activeBlockTitle,
            "activeBlockEndTime": activeBlockEndTime.timeIntervalSince1970,
            "isLive": isLive,
        ]
        if let nextBlockTitle {
            dict["nextBlockTitle"] = nextBlockTitle
        }
        if let nextBlockStartTime {
            dict["nextBlockStartTime"] = nextBlockStartTime.timeIntervalSince1970
        }
        if let sunsetTime {
            dict["sunsetTime"] = sunsetTime.timeIntervalSince1970
        }
        return dict
    }

    /// Decodes from a `[String: Any]` dictionary received via
    /// `session(_:didReceiveApplicationContext:)`.
    public init?(dictionary: [String: Any]) {
        guard let eventIDString = dictionary["eventID"] as? String,
              let eventID = UUID(uuidString: eventIDString),
              let eventTitle = dictionary["eventTitle"] as? String,
              let activeBlockTitle = dictionary["activeBlockTitle"] as? String,
              let activeBlockEndTimeInterval = dictionary["activeBlockEndTime"] as? TimeInterval,
              let isLive = dictionary["isLive"] as? Bool
        else {
            return nil
        }

        self.eventID = eventID
        self.eventTitle = eventTitle
        self.activeBlockTitle = activeBlockTitle
        self.activeBlockEndTime = Date(timeIntervalSince1970: activeBlockEndTimeInterval)
        self.isLive = isLive

        self.nextBlockTitle = dictionary["nextBlockTitle"] as? String

        if let interval = dictionary["nextBlockStartTime"] as? TimeInterval {
            self.nextBlockStartTime = Date(timeIntervalSince1970: interval)
        } else {
            self.nextBlockStartTime = nil
        }

        if let interval = dictionary["sunsetTime"] as? TimeInterval {
            self.sunsetTime = Date(timeIntervalSince1970: interval)
        } else {
            self.sunsetTime = nil
        }
    }
}
