import SwiftUI
import SwiftData
import Models
import Services

/// Lists all events sorted by date descending.
///
/// Uses `@Query` to reactively fetch `EventModel` objects from SwiftData.
/// Shows an empty state with a "+" button when no events exist.
struct EventRosterView: View {

    @Query(sort: \EventModel.date, order: .reverse)
    private var events: [EventModel]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if events.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .navigationTitle(String(localized: "Events"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addEvent()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Event"))
            }
        }
    }

    // MARK: - Subviews

    private var eventList: some View {
        List(events) { event in
            EventRowView(
                title: event.title,
                date: event.date,
                status: event.status
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No events yet"), systemImage: "calendar")
        } actions: {
            Button(String(localized: "Create Event")) {
                addEvent()
            }
        }
    }

    // MARK: - Actions

    private func addEvent() {
        let event = EventModel(
            title: "New Event",
            date: .now,
            latitude: 0,
            longitude: 0
        )
        modelContext.insert(event)
    }
}

// MARK: - Previews

#Preview("With Events") {
    NavigationStack {
        EventRosterView()
    }
    .modelContainer(previewContainerWithEvents())
}

#Preview("Empty State") {
    NavigationStack {
        EventRosterView()
    }
    .modelContainer(try! PersistenceController.forTesting())
}

@MainActor
private func previewContainerWithEvents() -> ModelContainer {
    let container = try! PersistenceController.forTesting()
    let context = container.mainContext
    let now = Date.now

    context.insert(EventModel(title: "Summer Wedding", date: now, latitude: 40.71, longitude: -74.00, status: .planning))
    context.insert(EventModel(title: "Corporate Gala", date: now.addingTimeInterval(-86400), latitude: 34.05, longitude: -118.24, status: .live))
    context.insert(EventModel(title: "Birthday Bash", date: now.addingTimeInterval(-172800), latitude: 37.77, longitude: -122.41, status: .completed))

    return container
}
