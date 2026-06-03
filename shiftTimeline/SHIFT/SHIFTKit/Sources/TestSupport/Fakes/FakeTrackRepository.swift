import Foundation
import Models
import Services

/// In-memory fake for `TrackRepositing`.
@MainActor
public final class FakeTrackRepository: TrackRepositing {

    public private(set) var tracks: [TimelineTrack] = []
    public private(set) var saveCallCount = 0

    public init() {}

    public func insert(_ track: TimelineTrack, into event: EventModel) async throws {
        track.event = event
        tracks.append(track)
    }

    public func fetch(id: UUID) async throws -> TimelineTrack? {
        tracks.first { $0.id == id }
    }

    public func fetchAll(for event: EventModel) async throws -> [TimelineTrack] {
        tracks
            .filter { $0.event?.id == event.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func delete(_ track: TimelineTrack) async throws {
        tracks.removeAll { $0.id == track.id }
    }

    public func save() async throws {
        saveCallCount += 1
    }
}
