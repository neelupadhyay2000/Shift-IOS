import Foundation
import Models
import SwiftData

@MainActor
public final class SwiftDataTrackRepository: TrackRepositing {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ track: TimelineTrack, into event: EventModel) async throws {
        track.event = event
        context.insert(track)
    }

    public func fetch(id: UUID) async throws -> TimelineTrack? {
        var descriptor = FetchDescriptor<TimelineTrack>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        (event.tracks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    public func delete(_ track: TimelineTrack) async throws {
        context.delete(track)
    }

    public func save() async throws {
        try context.save()
    }
}
