import Foundation
import SwiftData

@Model
public final class EventModel {
    public var id: UUID = UUID()
    public var title: String = ""
    public var date: Date = Date.distantPast
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var venueNames: [String] = []
    public var sunsetTime: Date?
    public var goldenHourStart: Date?
    public var weatherSnapshot: Data?
    public var status: EventStatus = EventStatus.planning

    /// CKShare URL for this event. Persisted so re-tapping "Share" opens the existing share.
    public var shareURL: String?

    /// CloudKit record name of the event creator. `nil` treated as current user owns it.
    public var ownerRecordName: String?

    /// When the event went live. Used for analytics session duration.
    public var wentLiveAt: Date?

    /// When the last block was completed. Used with `wentLiveAt` for analytics session duration.
    public var completedAt: Date?

    /// JSON-encoded `PostEventReport`. Access via `postEventReport` computed property.
    public var postEventReportData: Data?

    /// Decoded post-event report. Setting re-encodes to `postEventReportData`; `nil` clears it.
    public var postEventReport: PostEventReport? {
        get {
            guard let data = postEventReportData else { return nil }
            return try? JSONDecoder().decode(PostEventReport.self, from: data)
        }
        set {
            postEventReportData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    @Relationship(deleteRule: .cascade, inverse: \TimelineTrack.event)
    public var tracks: [TimelineTrack]?

    @Relationship(deleteRule: .cascade, inverse: \VendorModel.event)
    public var vendors: [VendorModel]?

    @Relationship(deleteRule: .cascade, inverse: \ShiftRecord.event)
    public var shiftRecords: [ShiftRecord]?

    /// `true` when current user owns the event. `true` for pre-feature events (`ownerRecordName == nil`).
    public func isOwnedBy(_ currentUserRecordName: String?) -> Bool {
        guard let ownerRecordName else { return true }
        guard let currentUserRecordName else { return false }
        return ownerRecordName == currentUserRecordName
    }

    /// Returns the `VendorModel` linked to the current iCloud user, if any.
    /// Used to scope block detail visibility for shared event recipients.
    public func vendorForUser(_ currentUserRecordName: String?) -> VendorModel? {
        guard let currentUserRecordName else { return nil }
        return (vendors ?? []).first { $0.cloudKitRecordName == currentUserRecordName }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        latitude: Double,
        longitude: Double,
        venueNames: [String] = [],
        sunsetTime: Date? = nil,
        goldenHourStart: Date? = nil,
        status: EventStatus = .planning
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.venueNames = venueNames
        self.sunsetTime = sunsetTime
        self.goldenHourStart = goldenHourStart
        self.status = status
    }
}
