import Foundation
import SwiftData

@Model
public final class EventModel {
    public var id: UUID = UUID()
    /// The Supabase profile that owns this event (`events.owner_id`). `nil` for a
    /// local-only event or one not yet stamped/backfilled with an owner. Drives
    /// owner-vs-shared gating: an event owned by a *different* signed-in profile
    /// is shown read-only (vendor/collaborator view, SHIFT-622).
    public var ownerId: UUID?
    public var title: String = ""
    public var date: Date = Date.distantPast
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var venueNames: [String] = []
    public var sunsetTime: Date?
    public var goldenHourStart: Date?
    public var weatherSnapshot: Data?
    public var status: EventStatus = EventStatus.planning

    /// Wall-clock timestamp when the event transitioned to `.live`.
    /// Set by `EventDetailView.startLiveMode`. Used to compute live-session
    /// duration for the `sessionCompleted` analytics signal.
    public var wentLiveAt: Date?

    /// Wall-clock timestamp when the final block was marked `.completed`.
    /// Set by `LiveDashboardView.performAdvance`. Used together with
    /// `wentLiveAt` to compute live-session duration in analytics.
    public var completedAt: Date?

    /// JSON-encoded `PostEventReport` produced when this event transitioned to
    /// `.completed`. Stored as raw `Data` so SwiftData can persist it.
    /// Access through the `postEventReport` computed property — never read this
    /// field directly.
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

    /// Server `updated_at` of the last remote version applied to this row — the
    /// basis for last-write-wins conflict resolution. `nil` for a row created
    /// locally that has never been reconciled with the server. Set by the
    /// Supabase mapping when a fetched/realtime/delta row is applied; never
    /// touched by local edits, so it stays the version a local edit is based on.
    public var updatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TimelineTrack.event)
    public var tracks: [TimelineTrack]?

    @Relationship(deleteRule: .cascade, inverse: \VendorModel.event)
    public var vendors: [VendorModel]?

    @Relationship(deleteRule: .cascade, inverse: \ShiftRecord.event)
    public var shiftRecords: [ShiftRecord]?

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
