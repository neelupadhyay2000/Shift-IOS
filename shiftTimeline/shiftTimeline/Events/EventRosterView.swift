import SwiftUI
import SwiftData
import UserNotifications
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
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.supabaseSyncStack) private var syncStack
    @Environment(\.eventRepository) private var injectedEventRepo
    @Environment(\.trackRepository) private var injectedTrackRepo
    @Environment(\.blockRepository) private var injectedBlockRepo

    /// Outbox-backed when sync is on (scene injection); SwiftData fallback otherwise.
    private var eventRepo: any EventRepositing {
        injectedEventRepo ?? SwiftDataEventRepository(context: modelContext)
    }

    private var trackRepo: any TrackRepositing {
        injectedTrackRepo ?? SwiftDataTrackRepository(context: modelContext)
    }

    private var blockRepo: any BlockRepositing {
        injectedBlockRepo ?? SwiftDataBlockRepository(context: modelContext)
    }

    @State private var isShowingCreateSheet = false
    @State private var searchText = ""
    @State private var statusFilter: EventStatusFilter = .all
    @State private var eventPendingDeletion: EventModel?
    @State private var isShowingPaywall = false

    private var filteredEvents: [EventModel] {
        let dismissed = SharedEventDismissalStore.dismissedIDs()
        return events.filter { event in
            // Skip models a deletion (e.g. the account-switch purge during
            // sign-in, or delta reconciliation) detached from the context.
            // Reading any persisted attribute on detached backing data is a
            // fatal SwiftData fault, so this guard must precede every other
            // property access below (including event.id).
            guard event.modelContext != nil, !event.isDeleted else { return false }
            guard !dismissed.contains(event.id) else { return false }
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
        .searchable(text: $searchText, prompt: String(localized: "Search events"))
        .navigationTitle(String(localized: "Events"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if events.count >= FreeTier.maxActiveEvents && !SubscriptionManager.shared.isProUser {
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
                    deleteOwnedEvent(event)
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
        .refreshable { await refresh() }
    }

    // MARK: - Subviews

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
                    let isOwner = EventAccess.isOwner(ownerId: event.ownerId, currentProfileID: authService.currentProfileID)
                    NavigationLink(value: EventDestination.eventDetail(id: event.id)) {
                        EventRowView(
                            title: event.title,
                            date: event.date,
                            status: event.status,
                            isShared: !isOwner
                        )
                        .proCard(padding: 14)
                    }
                    .buttonStyle(.pressableCard)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .contextMenu {
                        if isOwner {
                            Button(role: .destructive) {
                                eventPendingDeletion = event
                            } label: {
                                Label(String(localized: "Delete Event"), systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                removeSharedEvent(event)
                            } label: {
                                Label(String(localized: "Remove from My Events"), systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(.smooth(duration: 0.3), value: filteredEvents.map(\.id))
        }
        .background { ProBackground() }
        .accessibilityIdentifier(AccessibilityID.Roster.eventList)
    }

    private var emptyState: some View {
        // Wrapped in a ScrollView so pull-to-refresh works with no local events —
        // the case where a vendor pulls to fetch a freshly claimed shared event.
        ScrollView {
            ContentUnavailableView {
                Label(String(localized: "No events yet"), systemImage: "calendar")
            } actions: {
                Button(String(localized: "Create Event")) {
                    isShowingCreateSheet = true
                }
                .accessibilityIdentifier(AccessibilityID.Roster.createEventButton)

                // First-run conversion path: seed a ready-to-run sample event so
                // the user can Go Live and watch the Ripple Engine work without
                // building a timeline first.
                Button(String(localized: "Try a Demo Event")) {
                    seedDemoEvent()
                }
                .accessibilityIdentifier(AccessibilityID.Roster.demoEventButton)
                .accessibilityHint(String(localized: "Creates a sample event with a ready-made timeline"))
            }
            .containerRelativeFrame(.vertical, alignment: .center)
        }
    }

    // MARK: - Actions

    /// Seeds the demo event and pushes straight into its detail view.
    private func seedDemoEvent() {
        Task {
            guard let eventID = await DemoEventSeeder.seed(
                eventRepo: eventRepo, trackRepo: trackRepo, blockRepo: blockRepo
            ) else { return }
            deepLinkRouter.pendingDestination = .event(id: eventID)
        }
    }

    private func deleteOwnedEvent(_ event: EventModel) {
        // The event is going away — its pending local reminders must too.
        DayBeforeBriefingNotifier.cancel(for: event.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [GoldenHourNotifier.identifier(for: event.id)]
        )
        // Route through the repository so the delete reaches Supabase as a
        // soft-delete tombstone and every other device (vendors included)
        // converges via realtime/delta. A bare modelContext.delete stays
        // local-only: the event lingers on vendors' rosters and resurrects
        // here on the next full hydrate.
        Task {
            try? await eventRepo.delete(event)
            try? await eventRepo.save()
        }
    }

    /// Removes a *shared* event from this device. The planner remains the owner;
    /// this only clears the vendor's local copy.
    private func removeSharedEvent(_ event: EventModel) {
        SharedEventDismissalStore.dismiss(event.id)
        modelContext.delete(event)
        try? modelContext.save()
    }

    // MARK: - Sync

    /// Pull-to-refresh: drives the sync stack's flush + full hydrate so the signed-
    /// in user's complete accessible graph (RLS-scoped) is pulled — newly shared
    /// events and remote edits (shifts, acks) appear without relaunching the app.
    /// A full hydrate (not a delta) is what makes an older, newly shared event
    /// load. No-op when signed out or when Supabase sync is off.
    private func refresh() async {
        guard authService.isAuthenticated else { return }
        await syncStack?.refresh()
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
    .environment(SupabaseAuthService())
    .environment(DeepLinkRouter.shared)
    .modelContainer(previewContainerWithEvents())
}

#Preview("Empty State") {
    NavigationStack {
        EventRosterView()
    }
    .environment(SupabaseAuthService())
    .environment(DeepLinkRouter.shared)
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
