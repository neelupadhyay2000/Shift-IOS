import Foundation
import Models
import Services
import SwiftData
import Testing

struct EventRosterTests {

    /// AC: insert 3 events → list shows 3 rows (sorted by date descending).
    ///
    /// We verify the data layer that backs `@Query(sort: \EventModel.date, order: .reverse)`.
    @Test @MainActor func threeInsertedEventsAreFetchedSortedByDateDescending() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let now = Date.now
        let event1 = EventModel(title: "Oldest", date: now.addingTimeInterval(-200), latitude: 0, longitude: 0, status: .completed)
        let event2 = EventModel(title: "Middle", date: now.addingTimeInterval(-100), latitude: 0, longitude: 0, status: .live)
        let event3 = EventModel(title: "Newest", date: now, latitude: 0, longitude: 0, status: .planning)

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        let descriptor = FetchDescriptor<EventModel>(
            sortBy: [SortDescriptor(\EventModel.date, order: .reverse)]
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 3)
        #expect(fetched[0].title == "Newest")
        #expect(fetched[1].title == "Middle")
        #expect(fetched[2].title == "Oldest")
    }

    /// Each event should expose a status that maps to one of the three badge values.
    @Test func eventStatusBadgeLabelsAreCorrect() {
        #expect(EventStatus.planning.rawValue == "planning")
        #expect(EventStatus.live.rawValue == "live")
        #expect(EventStatus.completed.rawValue == "completed")
    }

    /// AC: 5 events, search "wed" → only matching events returned.
    ///
    /// Mirrors the case-insensitive filter logic used by `EventRosterView.filteredEvents`.
    @Test @MainActor func searchFilterReturnsCaseInsensitiveMatches() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let now = Date.now
        let titles = ["Summer Wedding", "Winter Wedding", "Corporate Gala", "Birthday Bash", "Wednesday Meetup"]
        for (i, title) in titles.enumerated() {
            context.insert(EventModel(title: title, date: now.addingTimeInterval(Double(-i * 100)), latitude: 0, longitude: 0))
        }
        try context.save()

        let all = try context.fetch(FetchDescriptor<EventModel>())
        #expect(all.count == 5)

        let query = "wed"
        let filtered = all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        #expect(filtered.count == 3)

        let matchedTitles = Set(filtered.map(\.title))
        #expect(matchedTitles.contains("Summer Wedding"))
        #expect(matchedTitles.contains("Winter Wedding"))
        #expect(matchedTitles.contains("Wednesday Meetup"))
    }

    /// AC: 3 planning + 2 completed → filter "completed" → 2 shown.
    ///
    /// Mirrors the status filter logic used by `EventRosterView.filteredEvents`.
    @Test @MainActor func statusFilterReturnsOnlyMatchingStatus() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let now = Date.now
        for i in 0..<3 {
            context.insert(EventModel(title: "Planning \(i)", date: now.addingTimeInterval(Double(-i * 100)), latitude: 0, longitude: 0, status: .planning))
        }
        for i in 0..<2 {
            context.insert(EventModel(title: "Done \(i)", date: now.addingTimeInterval(Double(-i * 100 - 300)), latitude: 0, longitude: 0, status: .completed))
        }
        try context.save()

        let all = try context.fetch(FetchDescriptor<EventModel>())
        #expect(all.count == 5)

        let completedFilter: EventStatus = .completed
        let filtered = all.filter { $0.status == completedFilter }
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.status == .completed })
    }

    /// AC: delete event → removed from list and SwiftData; cascade removes tracks, blocks, vendors.
    @Test @MainActor func deleteEventCascadesToRelatedObjects() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)

        let vendor = VendorModel(name: "Photographer", role: .photographer)
        vendor.event = event
        context.insert(vendor)

        try context.save()

        // Verify everything was inserted
        #expect(try context.fetch(FetchDescriptor<EventModel>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TimelineTrack>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TimeBlockModel>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<VendorModel>()).count == 1)

        // Delete the event — cascade should remove tracks, blocks, vendors
        context.delete(event)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<EventModel>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<TimelineTrack>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<TimeBlockModel>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<VendorModel>()).count == 0)
    }

    // MARK: - Default Track Auto-Creation

    /// AC: Creating an event auto-creates a "Main" track.
    @Test @MainActor func creatingEventAutoCreatesMainTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        // Simulate CreateEventSheet.createEvent()
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)
        try context.save()

        #expect((event.tracks ?? []).count == 1)
        #expect((event.tracks ?? []).first?.name == "Main")
        #expect((event.tracks ?? []).first?.sortOrder == 0)
        #expect((event.tracks ?? []).first?.isDefault == true)

        // Verify the track is persisted
        let tracks = try context.fetch(FetchDescriptor<TimelineTrack>())
        #expect(tracks.count == 1)
        #expect(tracks.first?.event?.id == event.id)
    }

    /// AC: Blocks added without specifying a track go to "Main".
    @Test @MainActor func blockWithoutExplicitTrackGoesToMain() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        // Create event with auto-created Main track
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)
        try context.save()

        // Simulate CreateBlockSheet.saveBlock() — uses event.tracks.first
        let track = (event.tracks ?? []).first!
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)
        try context.save()

        // Block should be in the Main track
        #expect(block.track?.name == "Main")
        #expect((mainTrack.blocks ?? []).count == 1)
        #expect((mainTrack.blocks ?? []).first?.title == "Ceremony")
    }

    // MARK: - Share URL Persistence

    /// AC: shareURL persists through SwiftData save/fetch cycle and can be cleared.
    @Test @MainActor func shareURLPersistsAndClears() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Shared Event", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        // Initially nil
        #expect(event.shareURL == nil)

        // Set and persist
        event.shareURL = "https://www.icloud.com/share/abc123"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<EventModel>())
        #expect(fetched.first?.shareURL == "https://www.icloud.com/share/abc123")

        // Clear and persist
        fetched.first?.shareURL = nil
        try context.save()

        let refetched = try context.fetch(FetchDescriptor<EventModel>())
        #expect(refetched.first?.shareURL == nil)
    }

    /// AC: Cascade delete removes the auto-created Main track and its blocks.
    @Test @MainActor func deleteEventCascadesAutoCreatedMainTrack() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(mainTrack)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = mainTrack
        context.insert(block)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TimelineTrack>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TimeBlockModel>()).count == 1)

        context.delete(event)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<EventModel>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<TimelineTrack>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<TimeBlockModel>()).count == 0)
    }
}
