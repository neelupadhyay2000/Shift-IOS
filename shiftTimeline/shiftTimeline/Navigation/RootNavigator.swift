import SwiftUI
import SwiftData

// MARK: - Tab

/// Top-level tab destinations for the iPhone tab bar.
///
/// Each case becomes a `TabView` tab on compact (iPhone) and a sidebar row
/// on regular (iPad). Additional cases will be added as E2 stories land.
enum Tab: String, Hashable, CaseIterable {
    case events   = "Events"
    case vendors  = "Vendors"
    case settings = "Settings"

    var systemImage: String {
        switch self {
        case .events:   "calendar"
        case .vendors:  "person.2"
        case .settings: "gearshape"
        }
    }
}

// MARK: - EventDestination

/// Typed navigation destinations pushed onto the event `NavigationStack` path.
///
/// Using a typed enum + `navigationDestination(for:)` instead of
/// `NavigationLink(destination:)` keeps navigation state serialisable and
/// testable. Additional cases will be added as timeline / inspector stories land.
enum EventDestination: Hashable {
    case eventDetail(id: UUID)
    case timelineBuilder(eventID: UUID)
}

// MARK: - RootNavigator

/// Adaptive root navigator: `NavigationStack` + `TabView` on iPhone (compact),
/// `NavigationSplitView` on iPad (regular).
///
/// Layout selection uses `horizontalSizeClass` from the environment — never
/// a device-model check — so the same binary adapts correctly to all form factors
/// including slide-over and split-screen multitasking.
///
/// **Placeholder state (Subtask 1):**
/// Navigation chrome is fully wired; individual destination views are stubs
/// (`ContentPlaceholderView`) that will be replaced in subsequent E2 stories.
struct RootNavigator: View {

    @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: Navigation state

    /// Active tab on iPhone / active sidebar selection on iPad.
    @State private var selectedTab: Tab = .events

    /// iPad sidebar selection — `List(selection:)` requires an optional binding.
    /// Kept in sync with `selectedTab` via `.onChange`.
    @State private var sidebarSelection: Tab? = .events

    /// Push path for the Events stack on iPhone.
    @State private var eventPath: [EventDestination] = []

    // MARK: Body

    var body: some View {
        if sizeClass == .compact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                NavigationStack(path: tab == .events ? $eventPath : .constant([])) {
                    ContentPlaceholderView(tab: tab)
                        .navigationDestination(for: EventDestination.self) { destination in
                            destinationView(for: destination)
                        }
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .navigationTitle(String(localized: "SHIFT"))
            .onChange(of: sidebarSelection) { _, newValue in
                if let tab = newValue { selectedTab = tab }
            }
        } detail: {
            NavigationStack(path: $eventPath) {
                ContentPlaceholderView(tab: selectedTab)
                    .navigationDestination(for: EventDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        }
    }

    // MARK: - Destination routing

    @ViewBuilder
    private func destinationView(for destination: EventDestination) -> some View {
        switch destination {
        case .eventDetail(let id):
            ContentPlaceholderView(label: "Event Detail — \(id.uuidString.prefix(8))")
        case .timelineBuilder(let eventID):
            ContentPlaceholderView(label: "Timeline Builder — \(eventID.uuidString.prefix(8))")
        }
    }
}

// MARK: - ContentPlaceholderView

/// Placeholder shown while downstream E2 stories are not yet implemented.
///
/// Replace each usage with the real destination view as stories land:
/// - `.events`  → `EventRosterView`
/// - `.vendors` → `VendorManagerView`
/// - `.settings` → `SettingsView`
private struct ContentPlaceholderView: View {

    var tab: Tab?
    var label: String?

    init(tab: Tab) {
        self.tab = tab
        self.label = nil
    }

    init(label: String) {
        self.tab = nil
        self.label = label
    }

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
        .background(Color(.systemGroupedBackground))
        .navigationTitle(label ?? tab?.rawValue ?? "")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Preview

#Preview("iPhone") {
    RootNavigator()
        .environment(\.horizontalSizeClass, .compact)
}

#Preview("iPad") {
    RootNavigator()
        .environment(\.horizontalSizeClass, .regular)
}
