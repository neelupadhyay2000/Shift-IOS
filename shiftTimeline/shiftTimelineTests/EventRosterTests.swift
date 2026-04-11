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
}
