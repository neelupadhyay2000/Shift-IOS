import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit
import TipKit
import TelemetryDeck
import Models
import Services
import TestSupport
import os

/// SHIFT app entry point.
///
/// `PersistenceController.shared.container` registers all five SwiftData models:
///   - EventModel
///   - TimelineTrack
///   - TimeBlockModel
///   - VendorModel
///   - ShiftRecord
///
/// The container is injected into the SwiftUI environment here so every
/// descendant view can use `@Query` and `@Environment(\.modelContext)` without
/// additional setup.
@main
struct shiftTimelineApp: App {

    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var watchSessionManager = WatchSessionManager()
    @State private var liveActivityManager = LiveActivityManager()
    private let deepLinkRouter = DeepLinkRouter.shared

    // MARK: - UI Test Mode

    /// `true` when the process was launched by the XCUITest runner with `-UITestMode 1`.
    /// Evaluated once at process start; safe to read from any context.
    static let isUITestMode = CommandLine.arguments.contains("-UITestMode")

    /// The active `ModelContainer` for this process.
    ///
    /// UI test runs receive an in-memory container with no CloudKit connectivity so
    /// tests never touch real user data. Production runs use the CloudKit-backed
    /// shared container from `PersistenceController`.
    private static let modelContainer: ModelContainer = {
        guard !isUITestMode else {
            do {
                return try PersistenceController.forTesting()
            } catch {
                fatalError("Failed to create in-memory ModelContainer for UI tests: \(error)")
            }
        }
        return PersistenceController.shared.container
    }()

    init() {
        guard !Self.isUITestMode else {
            Self.resetDataIfRequested()
            Self.seedFixtureIfRequested()
            return
        }
        SunsetPrefetchTask.register()
        SunsetPrefetchTask.scheduleNextRefresh()
        if CommandLine.arguments.contains("-ResetTipKit") {
            try? Tips.resetDatastore()
        }
        try? Tips.configure()

        TelemetryDeck.initialize(config: .init(appID: AnalyticsConstants.telemetryDeckAppID))
        // Forward every sync/share diagnostic event to TelemetryDeck so the
        // planner→vendor funnel is observable in the web dashboard.
        SyncDiagnosticsCenter.shared.addObserver { event in
            AnalyticsService.send(event)
        }
        AnalyticsService.send(.appLaunched)
    }

    /// Wipes all persistent state when the test runner passes `-ResetData 1`.
    ///
    /// Called synchronously in `init()` before SwiftUI renders the first scene,
    /// guaranteeing each test starts from a blank slate.
    ///
    /// What is reset:
    /// - Main-bundle `UserDefaults` domain (onboarding flags, cached preferences, etc.)
    /// - App Group `UserDefaults` domain (widget data store, shared prefs)
    ///
    /// What does NOT need resetting:
    /// - The `ModelContainer` — it is in-memory (`isStoredInMemoryOnly: true`) and
    ///   created fresh for every process launch, so it is already empty.
    private static func resetDataIfRequested() {
        guard CommandLine.arguments.contains("-ResetData") else { return }

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        let appGroupID = "group.com.neelsoftwaresolutions.shiftTimeline"
        UserDefaults(suiteName: appGroupID)?.removePersistentDomain(forName: appGroupID)
    }

    /// Seeds the in-memory `ModelContainer` with a deterministic fixture when
    /// the test runner passes `-SeedFixture <name>`.
    ///
    /// The fixture name is resolved via `TestFixture.named(_:)`. Time-dependent
    /// fixture data is stamped from `TestClock.fromLaunchArguments`, which
    /// reads `-FrozenNow <iso8601>` so countdowns and timers are reproducible
    /// across machines and CI runs.
    ///
    /// Silent no-op when:
    /// - The flag is absent.
    /// - The flag is present but the fixture name is unknown.
    /// - Building throws (logged; never crashes the app under test).
    @MainActor
    private static func seedFixtureIfRequested() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "-SeedFixture"),
              args.indices.contains(idx + 1) else { return }

        let name = args[idx + 1]
        guard let fixture = TestFixture.named(name) else {
            logger.error("Unknown -SeedFixture token '\(name, privacy: .public)'")
            return
        }

        let context = modelContainer.mainContext
        let clock = TestClock.fromLaunchArguments
        do {
            try fixture.build(into: context, clock: clock)
            try context.save()
            logger.info("Seeded fixture '\(name, privacy: .public)'")
        } catch {
            logger.error("Failed to seed fixture '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "com.shift.app", category: "Lifecycle")

    var body: some Scene {
        WindowGroup {
            RootNavigator()
                .environment(watchSessionManager)
                .environment(liveActivityManager)
                .environment(deepLinkRouter)
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                }
                .task {
                    guard !Self.isUITestMode else { return }
                    watchSessionManager.activate()
                    liveActivityManager.reclaimExistingActivity()
                }
        }
        .modelContainer(Self.modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard !Self.isUITestMode else { return }
            if newPhase == .background {
                SunsetPrefetchTask.scheduleNextRefresh()
            }
            if newPhase == .active {
                refreshWidgetNextEventDate()
            }
        }
    }

    /// Writes the next upcoming event date to the widget App Group store
    /// so the "No Active Event" widget state can show "Next event: …".
    private func refreshWidgetNextEventDate() {
        let context = PersistenceController.shared.container.mainContext
        let now = Date()
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.date >= now },
            sortBy: [SortDescriptor(\.date)]
        )

        if let nextEvent = try? context.fetch(descriptor).first {
            WidgetDataStore.writeNextEventDate(nextEvent.date)
        } else {
            WidgetDataStore.writeNextEventDate(nil)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "shiftTimelineWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ShiftMediumWidget")
    }
}

// MARK: - AppDelegate (local notifications + scene wiring)

/// Handles local notifications and scene delegate wiring.
/// CloudKit share acceptance and remote push (E15) are handled in a later epic.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "AppDelegate"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard !shiftTimelineApp.isUITestMode else { return true }
        let hasManifest = Bundle.main.infoDictionary?["UIApplicationSceneManifest"] != nil
        let delegateClass: AnyClass? = NSClassFromString("shiftTimeline.SHIFTSceneDelegate")
        Self.logger.info("Launch diagnostic — scene manifest present: \(hasManifest), SHIFTSceneDelegate class resolved: \(delegateClass != nil ? "YES" : "NO — MISSING")")
        UNUserNotificationCenter.current().delegate = self
        Task { await VendorShiftLocalNotifier.requestAuthorization() }
        return true
    }

    /// Wires `SHIFTSceneDelegate` as the scene delegate so scene-lifecycle
    /// callbacks are delivered to the correct class.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SHIFTSceneDelegate.self
        return config
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification tap — deep-link into the shared event or live session.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Live Activity restart notification — deep-link to Live Dashboard.
        if let isLiveRestart = userInfo["isLiveRestart"] as? Bool,
           isLiveRestart,
           let eventIDString = userInfo["eventID"] as? String,
           let eventID = UUID(uuidString: eventIDString) {
            Task { @MainActor in
                DeepLinkRouter.shared.pendingDestination = .live(id: eventID)
            }
            completionHandler()
            return
        }

        // Vendor shift notification — deep-link to event detail.
        if let eventIDString = userInfo[VendorShiftNotificationContent.eventIDKey] as? String,
           let eventID = UUID(uuidString: eventIDString) {
            Task { @MainActor in
                DeepLinkRouter.shared.pendingEventID = eventID
            }
        }
        completionHandler()
    }

    /// Show notifications even when app is in foreground — except for vendor
    /// shift notifications, which are surfaced in-app via `ShiftAcknowledgmentBanner`.
    /// Suppressing the banner prevents the planner from seeing a push notification
    /// for their own shift while on the live dashboard.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Vendor shift notifications carry a deterministic "shift-<UUID>" identifier.
        // The in-app ShiftAcknowledgmentBanner handles these when the app is visible.
        if notification.request.identifier.hasPrefix("shift-") {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
