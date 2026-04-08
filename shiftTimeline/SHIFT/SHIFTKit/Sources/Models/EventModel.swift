import Foundation
import SwiftData

@Model
public final class EventModel {
    public var id: UUID
    public var title: String
    public var date: Date
    public var latitude: Double
    public var longitude: Double
    public var venueNames: [String]
    public var sunsetTime: Date?
    public var goldenHourStart: Date?
    public var status: EventStatus

    @Relationship(deleteRule: .cascade, inverse: \TimelineTrack.event)
    public var tracks: [TimelineTrack] = []

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
