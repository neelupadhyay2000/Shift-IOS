import Foundation
import SwiftData

@Model
public final class TimelineTrack {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    /// Stable flag identifying the event's default track. Exactly one track
    /// per event should have `isDefault == true`. The default track cannot
    /// be renamed or deleted.
    public var isDefault: Bool
    public var event: EventModel?

    @Relationship(deleteRule: .cascade, inverse: \TimeBlockModel.track)
    public var blocks: [TimeBlockModel] = []

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isDefault: Bool = false,
        event: EventModel? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.event = event
    }
}
