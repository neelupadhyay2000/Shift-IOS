import SwiftUI
import SwiftData
import Services

// MARK: - Tab

/// Top-level tab destinations for the iPhone tab bar and iPad sidebar.
enum Tab: String, Hashable, CaseIterable {
    case events      = "Events"
    case marketplace = "Marketplace"
    case templates   = "Templates"
    case settings    = "Settings"

    var systemImage: String {
        switch self {
        case .events:      "calendar"
        case .marketplace: "storefront"
        case .templates:   "square.grid.2x2"
        case .settings:    "gearshape"
        }
    }
}

// MARK: - Navigation destination enums

/// Typed push destinations for the Events stack.
/// Add cases here as timeline / inspector stories land.
enum EventDestination: Hashable {
    case eventDetail(id: UUID)
    case timelineBuilder(eventID: UUID)
    case vendorManager(eventID: UUID)
    case pdfExport(eventID: UUID)
    case postEventReport(eventID: UUID)
    case liveDashboard(eventID: UUID)
}

/// Typed push destinations for the Marketplace stack. Replaces the E9
/// teaser-only routing now that the directory is being built.
enum MarketplaceDestination: Hashable {
    case vendorProfile(profileID: UUID)
    case searchResults
    case myVendorProfile
    case portfolioEditor
}

/// Typed push destinations for the Templates stack.
enum TemplateDestination: Hashable {
    case templatePreview(templateID: UUID)
    case timelineBuilder(eventID: UUID)
}

// MARK: - RootNavigator

/// Adaptive root navigator.
///
/// - **Compact (iPhone):** `TabView` where every tab owns a `NavigationStack`
///   backed by its own `@State` path array.
/// - **Regular (iPad):** `NavigationSplitView` with a sidebar tab list and a
///   detail `NavigationStack` driven by `detailPath`.
///
/// Layout is chosen via `@Environment(\.horizontalSizeClass)` — never a
/// device-model check — so the same binary handles iPhone, iPad, slide-over,
/// and split-screen correctly.
struct RootNavigator: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    // MARK: Shared selection state

    @State private var selectedTab: Tab = .events

    // iPad List requires an optional binding.
    @State private var sidebarSelection: Tab? = .events

    // iPad sidebar visibility — auto-collapses when a tab is selected.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    // MARK: Per-tab @State path arrays (AC: navigation state via @State path arrays)

    @State private var eventPath: [EventDestination] = []
    @State private var marketplacePath: [MarketplaceDestination] = []
    @State private var templatePath: [TemplateDestination] = []

    // iPad detail stack path — driven by whichever sidebar tab is active.
    @State private var detailPath: [EventDestination] = []

    /// Pending event ID set by .newEventTimeline routing.
    /// Applied in EventRosterView.onAppear so the push happens after the
    /// Events NavigationStack is in the view hierarchy on both iPhone and iPad.
    @State private var pendingEventID: UUID?

    // MARK: Body

    var body: some View {
        if sizeClass == .compact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone layout
    // Each tab has its own NavigationStack + path so every tab can
    // programmatically push/pop independently.

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            // Events tab
            NavigationStack(path: $eventPath) {
                EventRosterView()
                    .onAppear {
                        if let id = pendingEventID {
                            eventPath = [.eventDetail(id: id)]
                            pendingEventID = nil
                        }
                    }
                    .navigationDestination(for: EventDestination.self) { destination in
                        eventDestinationView(for: destination)
                    }
            }
            .tabItem { Label(Tab.events.rawValue, systemImage: Tab.events.systemImage) }
            .tag(Tab.events)

            // Marketplace tab
            NavigationStack(path: $marketplacePath) {
                MarketplaceTeaserView()
                    .navigationDestination(for: MarketplaceDestination.self) { destination in
                        marketplaceDestinationView(for: destination)
                    }
            }
            .tabItem { Label(Tab.marketplace.rawValue, systemImage: Tab.marketplace.systemImage) }
            .tag(Tab.marketplace)

            // Templates tab
            NavigationStack(path: $templatePath) {
                TemplateBrowserView()
                    .navigationDestination(for: TemplateDestination.self) { destination in
                        templateDestinationView(for: destination)
                    }
            }
            .tabItem { Label(Tab.templates.rawValue, systemImage: Tab.templates.systemImage) }
            .tag(Tab.templates)

            // Settings tab
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(Tab.settings.rawValue, systemImage: Tab.settings.systemImage) }
            .tag(Tab.settings)
        }
        .onChange(of: deepLinkRouter.pendingDestination) { _, destination in
            guard let destination else { return }
            routeToDestination(destination)
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $sidebarSelection) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .navigationTitle(String(localized: "SHIFT"))
            // CR2: keep sidebarSelection aligned when selectedTab changes externally
            // (e.g. size class flips from compact → regular while a tab is selected on iPhone)
            .onChange(of: selectedTab) { _, newTab in
                sidebarSelection = newTab
                detailPath = []
            }
            .onChange(of: sidebarSelection) { _, newValue in
                if let tab = newValue {
                    selectedTab = tab
                    detailPath = []
                    // Auto-collapse sidebar after selection for cleaner UX
                    withAnimation {
                        columnVisibility = .detailOnly
                    }
                }
            }
        } detail: {
            // CR1: swap the detail NavigationStack per selected tab so every tab
            // gets its own typed destinations on iPad — not just Events.
            iPadDetailStack
        }
        // CR2: when entering regular layout from compact, stamp sidebarSelection
        // from the current selectedTab so the sidebar highlight is always correct.
        .onChange(of: sizeClass) { _, newClass in
            if newClass != .compact {
                sidebarSelection = selectedTab
            }
        }
        .onChange(of: deepLinkRouter.pendingDestination) { _, destination in
            guard let destination else { return }
            // routeToDestination sets the tab/sidebar per destination.
            routeToDestination(destination)
        }
    }

    @ViewBuilder
    private var iPadDetailStack: some View {
        switch selectedTab {
        case .events:
            NavigationStack(path: $eventPath) {
                EventRosterView()
                    .onAppear {
                        if let id = pendingEventID {
                            eventPath = [.eventDetail(id: id)]
                            pendingEventID = nil
                        }
                    }
                    .navigationDestination(for: EventDestination.self) { destination in
                        eventDestinationView(for: destination)
                    }
            }
        case .marketplace:
            NavigationStack(path: $marketplacePath) {
                MarketplaceTeaserView()
                    .navigationDestination(for: MarketplaceDestination.self) { destination in
                        marketplaceDestinationView(for: destination)
                    }
            }
        case .templates:
            NavigationStack(path: $templatePath) {
                TemplateBrowserView()
                    .navigationDestination(for: TemplateDestination.self) { destination in
                        templateDestinationView(for: destination)
                    }
            }
        case .settings:
            NavigationStack {
                SettingsView()
            }
        }
    }

    // MARK: - Deep-Link Routing

    private func routeToDestination(_ destination: DeepLinkDestination) {
        switch destination {
        case .event(let id):
            selectTab(.events)
            eventPath = [.eventDetail(id: id)]
        case .live(let id):
            selectTab(.events)
            eventPath = [.eventDetail(id: id), .liveDashboard(eventID: id)]
        case .roster:
            selectTab(.events)
            eventPath = []
        case .newEventTimeline(let id):
            // Reset the template stack so the user returns cleanly to the
            // template browser if they switch back to the Templates tab.
            templatePath = []
            // Store the target ID and switch tabs. The push onto eventPath
            // is deferred to EventRosterView.onAppear so it fires after the
            // Events NavigationStack enters the hierarchy on iPad.
            // (On iPhone the TabView keeps all stacks live, so onAppear fires
            // on the next tab-switch cycle — same reliable timing.)
            pendingEventID = id
            selectTab(.events)
        case .vendorProfile(let id):
            // shift://vendor/{id} → Marketplace tab, push the public profile.
            selectTab(.marketplace)
            marketplacePath = [.vendorProfile(profileID: id)]
        }
        deepLinkRouter.pendingDestination = nil
    }

    /// Switches the active tab and keeps the iPad sidebar selection aligned.
    private func selectTab(_ tab: Tab) {
        selectedTab = tab
        sidebarSelection = tab
    }

    // MARK: - Destination routing

    @ViewBuilder
    private func eventDestinationView(for destination: EventDestination) -> some View {
        switch destination {
        case .eventDetail(let id):
            EventDetailView(eventID: id)
        case .timelineBuilder(let eventID):
            TimelineBuilderView(eventID: eventID)
        case .vendorManager(let eventID):
            VendorManagerView(eventID: eventID)
        case .pdfExport(let eventID):
            PDFExportPreviewView(eventID: eventID)
        case .postEventReport(let eventID):
            PostEventReportPreviewView(eventID: eventID)
        case .liveDashboard(let eventID):
            LiveDashboardView(eventID: eventID)
        }
    }

    @ViewBuilder
    private func marketplaceDestinationView(for destination: MarketplaceDestination) -> some View {
        switch destination {
        case .vendorProfile(let profileID):
            VendorPublicProfileView(profileID: profileID)
        case .searchResults:
            VendorSearchResultsView()
        case .myVendorProfile:
            MyVendorProfileView()
        case .portfolioEditor:
            PortfolioEditorView()
        }
    }

    @ViewBuilder
    private func templateDestinationView(for destination: TemplateDestination) -> some View {
        switch destination {
        case .templatePreview(let templateID):
            TemplatePreviewView(templateID: templateID)
        case .timelineBuilder(let eventID):
            TimelineBuilderView(eventID: eventID)
        }
    }
}

// MARK: - Previews

#Preview("iPhone — compact") {
    RootNavigator()
        .environment(\.horizontalSizeClass, .compact)
        .modelContainer(try! PersistenceController.forTesting())
}

#Preview("iPad — regular") {
    RootNavigator()
        .environment(\.horizontalSizeClass, .regular)
        .modelContainer(try! PersistenceController.forTesting())
}
