import Foundation
import SwiftData

/// Placeholder for the full TimeBlockModel definition (upcoming ticket).
@Model
public final class TimeBlockModel {
    public var id: UUID
    public var title: String
    public var track: TimelineTrack?

    public init(
        id: UUID = UUID(),
        title: String = ""
    ) {
        self.id = id
        self.title = title
    }
}
