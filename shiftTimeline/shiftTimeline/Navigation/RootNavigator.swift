import SwiftUI
import SwiftData
import Services

// MARK: - Tab

/// Top-level tab destinations for the iPhone tab bar and iPad sidebar.
enum Tab: String, Hashable, CaseIterable {
    case events    = "Events"
    case templates = "Templates"
    case settings  = "Settings"

    var systemImage: String {
        switch self {
        case .events:    "calendar"
        case .templates: "square.grid.2x2"
        case .settings:  "gearshape"
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

/// Typed push destinations for the Templates stack.
enum TemplateDestination: Hashable {
    case templatePreview(templateID: UUID)
    case timelineBuilder(eventID: UUID)
}

/// Typed push destinations for the Settings stack.
enum SettingsDestination: Hashable {
    case licences
    case about
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
    @State private var templatePath: [TemplateDestination] = []
    @State private var settingsPath: [SettingsDestination] = []

    // iPad detail stack path — driven by whichever sidebar tab is active.
    @State private var detailPath: [EventDestination] = []

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
                    .navigationDestination(for: EventDestination.self) { destination in
                        eventDestinationView(for: destination)
                    }
            }
            .tabItem { Label(Tab.events.rawValue, systemImage: Tab.events.systemImage) }
            .tag(Tab.events)

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
            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        settingsDestinationView(for: destination)
                    }
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
            sidebarSelection = .events
            routeToDestination(destination)
        }
    }

    @ViewBuilder
    private var iPadDetailStack: some View {
        switch selectedTab {
        case .events:
            NavigationStack(path: $eventPath) {
                EventRosterView()
                    .navigationDestination(for: EventDestination.self) { destination in
                        eventDestinationView(for: destination)
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
            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        settingsDestinationView(for: destination)
                    }
            }
        }
    }

    // MARK: - Deep-Link Routing

    private func routeToDestination(_ destination: DeepLinkDestination) {
        selectedTab = .events
        switch destination {
        case .event(let id):
            eventPath = [.eventDetail(id: id)]
        case .live(let id):
            eventPath = [.eventDetail(id: id), .liveDashboard(eventID: id)]
        case .roster:
            eventPath = []
        }
        deepLinkRouter.pendingDestination = nil
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
    private func templateDestinationView(for destination: TemplateDestination) -> some View {
        switch destination {
        case .templatePreview(let templateID):
            TemplatePreviewView(templateID: templateID, templatePath: $templatePath)
        case .timelineBuilder(let eventID):
            TimelineBuilderView(eventID: eventID)
        }
    }

    @ViewBuilder
    private func settingsDestinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .licences:
            ContentPlaceholderView(label: "Licences")
        case .about:
            ContentPlaceholderView(label: "About SHIFT")
        }
    }
}

// MARK: - ContentPlaceholderView

/// Placeholder root content for each tab.
/// Replaced by real views as E2 stories land:
///   `.events`    → EventRosterView  (done)
///   `.templates` → TemplateGalleryView
///   `.settings`  → SettingsView
private struct ContentPlaceholderView: View {

    var tab: Tab?
    var label: String?

    init(tab: Tab) { self.tab = tab }
    init(label: String) { self.label = label }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tab?.systemImage ?? "rectangle.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(label ?? tab?.rawValue ?? "")
                .font(.title2)
                .fontWeight(.medium)
            Text(String(localized: "Coming soon"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WarmBackground() }
        .navigationTitle(label ?? tab?.rawValue ?? "")
        .navigationBarTitleDisplayMode(.large)
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
