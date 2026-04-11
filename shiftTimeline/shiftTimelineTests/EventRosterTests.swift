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
}
