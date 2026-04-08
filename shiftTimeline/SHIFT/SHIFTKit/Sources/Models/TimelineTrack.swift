import Foundation
import SwiftData

@Model
public final class TimelineTrack {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var event: EventModel?

    @Relationship(deleteRule: .cascade, inverse: \TimeBlockModel.track)
    public var blocks: [TimeBlockModel] = []

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        event: EventModel? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.event = event
    }
}
