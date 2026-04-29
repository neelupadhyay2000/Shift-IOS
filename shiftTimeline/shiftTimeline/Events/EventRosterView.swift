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
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var isShowingCreateSheet = false
    @State private var searchText = ""
    @State private var statusFilter: EventStatusFilter = .all
    @State private var eventPendingDeletion: EventModel?
    @State private var isShowingPaywall = false

    private var filteredEvents: [EventModel] {
        events.filter { event in
            let matchesSearch = searchText.isEmpty || event.title.localizedCaseInsensitiveContains(searchText)
            let matchesStatus: Bool = if let requiredStatus = statusFilter.eventStatus {
                event.status == requiredStatus
            } else {
                true
            }
            return matchesSearch && matchesStatus
        }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if deepLinkRouter.isAcceptingShare {
                shareAcceptanceBanner
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "Search events"))
        .navigationTitle(String(localized: "Events"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if events.count >= 1 && !SubscriptionManager.shared.isProUser {
                        isShowingPaywall = true
                    } else {
                        isShowingCreateSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Event"))
                .accessibilityIdentifier(AccessibilityID.Roster.addEventButton)
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateEventSheet()
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .eventLimit)
        }
        .alert(
            String(localized: "Delete Event"),
            isPresented: Binding(
                get: { eventPendingDeletion != nil },
                set: { if !$0 { eventPendingDeletion = nil } }
            )
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let event = eventPendingDeletion {
                    modelContext.delete(event)
                    eventPendingDeletion = nil
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                eventPendingDeletion = nil
            }
        } message: {
            if let event = eventPendingDeletion {
                Text(String(localized: "Are you sure you want to delete \"\(event.title)\"? This will also remove all tracks, blocks, and vendors."))
            }
        }
    }

    // MARK: - Subviews

    private var shareAcceptanceBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "Syncing shared event…"))
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Syncing shared event"))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Status filter
                Picker(String(localized: "Status"), selection: $statusFilter) {
                    ForEach(EventStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .accessibilityIdentifier(AccessibilityID.Roster.statusFilter)

                ForEach(filteredEvents) { event in
                    NavigationLink(value: EventDestination.eventDetail(id: event.id)) {
                        EventRowView(
                            title: event.title,
                            date: event.date,
                            status: event.status,
                            isShared: !event.isOwnedBy(CloudKitIdentity.shared.currentUserRecordName)
                        )
                        .premiumCard()
                    }
                    .buttonStyle(.plain)
                    .scrollFade()
                    .contextMenu {
                        if event.isOwnedBy(CloudKitIdentity.shared.currentUserRecordName) {
                            Button(role: .destructive) {
                                eventPendingDeletion = event
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background { WarmBackground() }
        .accessibilityIdentifier(AccessibilityID.Roster.eventList)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No events yet"), systemImage: "calendar")
        } actions: {
            Button(String(localized: "Create Event")) {
                isShowingCreateSheet = true
            }
            .accessibilityIdentifier(AccessibilityID.Roster.createEventButton)
        }
    }
}

// MARK: - EventStatusFilter

enum EventStatusFilter: String, CaseIterable, Identifiable {
    case all
    case planning
    case live
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       String(localized: "All")
        case .planning:  String(localized: "Planning")
        case .live:      String(localized: "Live")
        case .completed: String(localized: "Completed")
        }
    }

    var eventStatus: EventStatus? {
        switch self {
        case .all:       nil
        case .planning:  .planning
        case .live:      .live
        case .completed: .completed
        }
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
