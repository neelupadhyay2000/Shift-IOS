import Foundation
import SwiftData

@Model
public final class ShiftRecord {
    public var id: UUID
    public var timestamp: Date
    public var deltaMinutes: Int
    public var triggeredBy: ShiftSource
    public var sourceBlock: TimeBlockModel?
    public var event: EventModel?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        deltaMinutes: Int,
        triggeredBy: ShiftSource,
        sourceBlock: TimeBlockModel? = nil,
        event: EventModel? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.deltaMinutes = deltaMinutes
        self.triggeredBy = triggeredBy
        self.sourceBlock = sourceBlock
        self.event = event
    }
}
