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
    public var status: EventStatus = EventStatus.planning

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
