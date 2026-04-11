import SwiftUI
import SwiftData
import Models
import Services

/// Displays a vertical list of time blocks for a given event, sorted chronologically.
///
/// Blocks are fetched via the event's tracks relationship.
/// Shows an empty state when no blocks exist.
struct TimelineBuilderView: View {

    @Query private var results: [EventModel]

    private let eventID: UUID

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    private var event: EventModel? { results.first }

    private var sortedBlocks: [TimeBlockModel] {
        guard let event else { return [] }
        return event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        Group {
            if sortedBlocks.isEmpty {
                emptyState
            } else {
                blockList
            }
        }
        .navigationTitle(event?.title ?? String(localized: "Timeline"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Subviews

    private var blockList: some View {
        List(sortedBlocks) { block in
            TimeBlockRowView(
                title: block.title,
                scheduledStart: block.scheduledStart,
                duration: block.duration,
                isPinned: block.isPinned,
                colorTag: block.colorTag
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Add your first block"), systemImage: "clock.badge.plus")
        }
    }
}

// MARK: - Previews

#Preview("With Blocks") {
    NavigationStack {
        TimelineBuilderView(eventID: previewEventID)
    }
    .modelContainer(previewTimelineContainer())
}

#Preview("Empty State") {
    NavigationStack {
        TimelineBuilderView(eventID: previewEmptyEventID)
    }
    .modelContainer(previewEmptyTimelineContainer())
}

private let previewEventID = UUID()
private let previewEmptyEventID = UUID()

@MainActor
private func previewTimelineContainer() -> ModelContainer {
    let container = try! PersistenceController.forTesting()
    let context = container.mainContext
    let base = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!

    let event = EventModel(id: previewEventID, title: "Summer Wedding", date: base, latitude: 40.71, longitude: -74.00)
    context.insert(event)

    let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
    context.insert(track)

    let blocks: [(String, TimeInterval, TimeInterval, Bool, String)] = [
        ("Ceremony", 0, 1800, true, "#FF5733"),
        ("Cocktail Hour", 1800, 3600, false, "#007AFF"),
        ("Dinner", 5400, 5400, true, "#34C759"),
    ]
    for (title, offset, duration, pinned, color) in blocks {
        let block = TimeBlockModel(
            title: title,
            scheduledStart: base.addingTimeInterval(offset),
            duration: duration,
            isPinned: pinned,
            colorTag: color
        )
        block.track = track
        context.insert(block)
    }

    return container
}

@MainActor
private func previewEmptyTimelineContainer() -> ModelContainer {
    let container = try! PersistenceController.forTesting()
    let context = container.mainContext
    let event = EventModel(id: previewEmptyEventID, title: "Empty Event", date: .now, latitude: 0, longitude: 0)
    context.insert(event)
    return container
}
