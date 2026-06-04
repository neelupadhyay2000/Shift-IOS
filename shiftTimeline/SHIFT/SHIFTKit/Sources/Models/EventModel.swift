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

    /// The URL string of the share link associated with this event, if shared.
    public var shareURL: String?

    /// The identity record name of the event creator.
    /// Set at creation time so shared recipients can detect they don't own the event.
    /// `nil` for events created before this field was added — treated as "owned by current user".
    public var ownerRecordName: String?

    /// Wall-clock timestamp when the event transitioned to `.live`.
    /// Set by `EventDetailView.startLiveMode`. Used to compute live-session
    /// duration for the `sessionCompleted` analytics signal.
    public var wentLiveAt: Date?

    /// Wall-clock timestamp when the final block was marked `.completed`.
    /// Set by `LiveDashboardView.performAdvance`. Used together with
    /// `wentLiveAt` to compute live-session duration in analytics.
    public var completedAt: Date?

    /// Wall-clock timestamp of the most recent mutation (shift, block add/edit/delete,
    /// event edit). Bumped via `touchForSync()` before every save so consumers can
    /// detect that something changed without diffing the full model graph.
    public var lastShiftedAt: Date?

    /// Records the current time as the mutation timestamp. Call immediately before
    /// `modelContext.save()` on any change that should be visible to sync consumers.
    public func touchForSync() {
        lastShiftedAt = .now
    }

    /// JSON-encoded `PostEventReport` produced when this event transitioned to
    /// `.completed`. Stored as raw `Data` so SwiftData can persist and CloudKit
    /// can mirror it without a custom value transformer. Access through the
    /// `postEventReport` computed property — never read this field directly.
    public var postEventReportData: Data?

    /// Decoded post-event report, or `nil` if no report has been generated yet
    /// (or if the stored payload can't be decoded — e.g. cross-version drift).
    /// Setting this property re-encodes and writes back to `postEventReportData`;
    /// setting `nil` clears the stored payload.
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

    /// Returns `true` when the supplied identity string matches the event owner.
    /// Returns `true` for pre-sharing events (`ownerRecordName == nil`).
    /// Returns `false` when the event has an owner but the identity is unknown.
    public func isOwnedBy(_ currentUserRecordName: String?) -> Bool {
        guard let ownerRecordName else { return true }
        guard let currentUserRecordName else { return false }
        return ownerRecordName == currentUserRecordName
    }

    /// Returns the `VendorModel` whose identity record matches the supplied string.
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
