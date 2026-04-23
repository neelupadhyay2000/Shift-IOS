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

    /// The URL string of the CKShare associated with this event, if shared.
    /// Persisted so re-tapping "Share" opens the existing share for management
    /// instead of creating a duplicate.
    public var shareURL: String?

    /// The CloudKit user record name of the event creator.
    /// Set at creation time so shared recipients can detect they don't own the event.
    /// `nil` for events created before this field was added — treated as "owned by current user".
    public var ownerRecordName: String?

    @Relationship(deleteRule: .cascade, inverse: \TimelineTrack.event)
    public var tracks: [TimelineTrack]?

    @Relationship(deleteRule: .cascade, inverse: \VendorModel.event)
    public var vendors: [VendorModel]?

    @Relationship(deleteRule: .cascade, inverse: \ShiftRecord.event)
    public var shiftRecords: [ShiftRecord]?

    /// Returns `true` when the current user is the event owner (planner).
    /// Returns `true` for pre-feature events (`ownerRecordName == nil`).
    /// Returns `false` when the event has an owner but the current user's
    /// identity is unknown — this prevents shared events from appearing
    /// editable before iCloud identity is fetched.
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
