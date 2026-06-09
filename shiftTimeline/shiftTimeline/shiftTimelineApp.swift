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
    @State private var authService = SupabaseAuthService()
    @State private var watchSessionManager = WatchSessionManager()
    @State private var liveActivityManager = LiveActivityManager()
    /// The E16 cutover composition root (SHIFT-658). Built once in `bootstrap()`
    /// when `FeatureFlags.supabaseSync` is on; `nil` keeps the app fully local.
    @State private var syncStack: SupabaseSyncStack?
    private let deepLinkRouter = DeepLinkRouter.shared

    // MARK: - UI Test Mode

    /// `true` when the process was launched by the XCUITest runner with `-UITestMode 1`.
    /// Evaluated once at process start; safe to read from any context.
    static let isUITestMode = CommandLine.arguments.contains("-UITestMode")

    /// `true` when XCTest/Swift Testing is hosting the process.
    /// `XCTestSessionIdentifier` is injected by Xcode into every test run.
    /// Used to skip initializations that require build-time secrets (e.g. Supabase).
    static let isUnitTestMode = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

    /// The active `ModelContainer` for this process.
    ///
    /// UI test runs receive an in-memory container so tests never touch real user data.
    /// Production runs use the on-disk shared container from `PersistenceController`.
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
            RootContainerView()
                .repositories(effectiveProvider)
                .environment(authService)
                .environment(watchSessionManager)
                .environment(liveActivityManager)
                .environment(deepLinkRouter)
                .environment(\.realtimeEchoSuppressor, syncStack?.echoSuppressor)
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                    // A tapped vendor invite (shift://invite/…): re-run the
                    // identity-based claim and re-hydrate so the shared event
                    // appears even for an already-signed-in vendor (the sign-in
                    // claim ran once, before this invite existed). A signed-out
                    // vendor claims on sign-in; the routed destination shows the
                    // event once access lands.
                    if url.scheme == "shift",
                       url.host == VendorInviteLink.host,
                       authService.isAuthenticated {
                        Task {
                            await authService.claimPendingInvites()
                            await syncStack?.onSessionEstablished()
                        }
                    }
                }
                .task { await bootstrap() }
        }
        .modelContainer(Self.modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard !Self.isUITestMode else { return }
            if newPhase == .background {
                SunsetPrefetchTask.scheduleNextRefresh()
            }
            if newPhase == .active {
                refreshWidgetNextEventDate()
                // Catch up on changes missed while realtime was disconnected, then
                // drain any writes queued offline (SHIFT-658).
                if let syncStack {
                    Task { await syncStack.reconcileOnForeground() }
                }
            }
        }
    }

    /// The repository bundle injected at the scene root. When the Supabase sync
    /// stack is live, every write routes through the Outbox (and on to Supabase);
    /// otherwise (flag off / tests) writes stay local via a SwiftData provider.
    private var effectiveProvider: any RepositoryProviding {
        if let provider = syncStack?.repositoryProvider {
            return provider
        }
        return SwiftDataRepositoryProvider(context: Self.modelContainer.mainContext)
    }

    /// One-time launch wiring: build the Supabase sync stack (when enabled), start
    /// auth, and activate the watch / live-activity managers. The `syncStack == nil`
    /// and `listenerTask` guards make a re-invocation safe.
    @MainActor
    private func bootstrap() async {
        guard !Self.isUITestMode else { return }
        if !Self.isUnitTestMode {
            let client = SupabaseClientProvider.shared.client
            let context = PersistenceController.shared.container.mainContext

            // E16 cutover (SHIFT-658): build the sync stack and route writes
            // through its Outbox provider when the master flag is on. Backfill and
            // hydration run as post-session side effects inside the auth service.
            var sessionSync: (any SessionSyncing)?
            var backfiller: (any DataBackfilling)?
            if FeatureFlags.supabaseSync {
                if syncStack == nil {
                    let stack = SupabaseSyncStack(
                        client: client,
                        context: context,
                        currentOwnerID: { [weak authService] in authService?.currentProfileID }
                    )
                    syncStack = stack
                    stack.start()
                }
                sessionSync = syncStack
                backfiller = DataBackfillRunner(context: context)
            }

            // Wire the APNs registrar before listening so a restored session
            // immediately registers the device token (SHIFT-642).
            await DeviceTokenRegistrar.shared.configure(
                writer: SupabaseDeviceTokenWriter(client: client)
            )
            authService.startListening(
                client: client,
                profileRepository: SupabaseProfileRepository(client: client),
                inviteClaimer: SupabaseInviteClaimer(client: client),
                deviceTokenRegistrar: DeviceTokenRegistrar.shared,
                dataBackfiller: backfiller,
                sessionSync: sessionSync,
                modelContext: context
            )
        }
        watchSessionManager.activate()
        liveActivityManager.reclaimExistingActivity()
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
        // Register with APNs every launch so we always have the current token
        // (Apple delivers it via didRegisterForRemoteNotifications). SHIFT-642.
        application.registerForRemoteNotifications()
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

    // MARK: - APNs registration (SHIFT-642)

    /// APNs delivered a device token — hand it to the registrar, which upserts it
    /// into `device_tokens` once a profile is signed in.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await DeviceTokenRegistrar.shared.updateAPNsToken(deviceToken) }
    }

    /// APNs registration failed — surface in diagnostics; nothing to register.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
        SyncDiagnosticsCenter.shared.record(
            .push, "apnsRegistrationFailed",
            params: ["error": String(describing: error)],
            severity: .error
        )
    }

    /// Background (content-available) shift push from the shift-notify Edge
    /// Function (SHIFT-646): wake → post the rich local notification via the
    /// existing notifier. Non-shift pushes are ignored.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let payload = RemoteShiftPushHandler.parse(userInfo) else {
            completionHandler(.noData)
            return
        }
        let container = PersistenceController.shared.container
        Task {
            let handled = await RemoteShiftPushHandler.handle(payload: payload, container: container)
            completionHandler(handled ? .newData : .noData)
        }
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

        // Vendor shift notification — deep-link to event detail (SHIFT-647).
        // Parse off the MainActor (Sendable payload), then route on it.
        if let payload = RemoteShiftPushHandler.parse(userInfo) {
            Task { @MainActor in
                RemoteShiftPushHandler.routeTap(payload, router: .shared)
            }
        }
        completionHandler()
    }

    /// Show notifications even when the app is in the foreground — except for
    /// vendor shift notifications (SHIFT-648). Those are suppressed as a system
    /// banner and surfaced as an in-app banner instead, so the user isn't
    /// double-notified for a shift they're already looking at.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Vendor shift notifications carry a deterministic "shift-<UUID>" identifier.
        let request = notification.request
        guard request.identifier.hasPrefix("shift-") else {
            completionHandler([.banner, .sound])
            return
        }

        // Foreground: suppress the system banner and surface it in-app instead.
        // Extract the Sendable banner on this actor, then publish on the MainActor.
        if let banner = RemoteShiftPushHandler.makeForegroundBanner(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            userInfo: request.content.userInfo
        ) {
            Task { @MainActor in DeepLinkRouter.shared.foregroundShiftBanner = banner }
        }
        completionHandler([])
    }
}
