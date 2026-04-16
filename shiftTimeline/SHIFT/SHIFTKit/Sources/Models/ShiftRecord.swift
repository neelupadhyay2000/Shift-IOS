import Foundation
import SwiftData

@Model
public final class ShiftRecord {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var deltaMinutes: Int = 0
    public var triggeredBy: ShiftSource = ShiftSource.manual
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
