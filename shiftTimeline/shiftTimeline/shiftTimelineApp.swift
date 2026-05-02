import SwiftUI
import SwiftData
import CloudKit
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

    /// One-time migration: stamps existing events with the current user's
    /// CloudKit record name so the shared-event detection works for
    /// events created before `ownerRecordName` was introduced.
    @MainActor
    private func backfillOwnerRecordNames() {
        guard let recordName = CloudKitIdentity.shared.currentUserRecordName else { return }
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate<EventModel> { $0.ownerRecordName == nil }
        )
        do {
            let events = try context.fetch(descriptor)
            guard !events.isEmpty else { return }
            for event in events {
                event.ownerRecordName = recordName
            }
            try context.save()
            Self.logger.info("Backfilled ownerRecordName for \(events.count) events")
        } catch {
            Self.logger.error("Failed to backfill ownerRecordNames: \(error.localizedDescription)")
        }
    }

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
                    await CloudKitIdentity.shared.fetchAndCache()
                    backfillOwnerRecordNames()
                    await SharedZoneSubscriptionManager.shared.registerIfNeeded()
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

// MARK: - CloudKit Share Acceptance & Silent Push

/// Handles:
/// 1. Incoming CKShare invitations when a vendor taps a share link.
/// 2. Remote notification registration for silent-push-based sync.
/// 3. Silent push handling — triggers shared-zone change fetch so the
///    vendor's local SwiftData store stays current after planner edits.
/// 4. Local notification tap → deep-link into the shared event.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "CloudSharing"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard !shiftTimelineApp.isUITestMode else { return true }
        // Diagnostic: confirm scene manifest and delegate class are present in the deployed binary.
        let hasManifest = Bundle.main.infoDictionary?["UIApplicationSceneManifest"] != nil
        let delegateClass: AnyClass? = NSClassFromString("shiftTimeline.SHIFTSceneDelegate")
        Self.logger.info("Launch diagnostic — scene manifest present: \(hasManifest), SHIFTSceneDelegate class resolved: \(delegateClass != nil ? "YES" : "NO — MISSING")")
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = self
        Task { await VendorShiftLocalNotifier.requestAuthorization() }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.logger.info("Registered for remote notifications")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit silent push — fetch shared-zone changes.
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.subscriptionID == SharedZoneSubscriptionManager.subscriptionID else {
            completionHandler(.noData)
            return
        }

        Task {
            let hasNewData = await SharedZoneSubscriptionManager.shared.fetchChanges()
            if hasNewData {
                await processVendorShiftNotifications()
            }
            completionHandler(hasNewData ? .newData : .noData)
        }
    }

    /// Programmatically wires `SHIFTSceneDelegate` as the scene delegate for every
    /// new window-scene session. This is more reliable than the Info.plist
    /// `UISceneDelegateClassName` string approach because:
    ///  - It passes the class reference directly — no ObjC name-string lookup.
    ///  - It cannot be defeated by Release-build dead-stripping.
    ///  - It takes precedence over the plist entry when both are present.
    ///
    /// Without this method, `UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`
    /// never fires even when `SHIFTSceneDelegate` is listed in Info.plist.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SHIFTSceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        AppDelegate.handleAcceptedShare(metadata: cloudKitShareMetadata)
    }

    // MARK: - Shared share-acceptance handler

    /// Test-only seam. When non-nil, `handleAcceptedShare(metadata:)` invokes
    /// this closure and returns instead of running the production CloudKit
    /// acceptance flow. Used by unit tests to verify that both delegate entry
    /// points route through the same shared handler. `CKShare.Metadata` has no
    /// public initializer, so the seam exposes a no-argument trigger
    /// (`fireShareAcceptanceTestHook`) for tests that cannot synthesize one.
    @MainActor
    static var handleAcceptedShareForTesting: (() -> Void)?

    /// Test-only convenience that fires `handleAcceptedShareForTesting` without
    /// requiring a `CKShare.Metadata`. Production code never calls this.
    @MainActor
    static func fireShareAcceptanceTestHook() {
        handleAcceptedShareForTesting?()
    }

    /// Single, canonical share-acceptance entry point. Both the application-delegate
    /// (`application(_:userDidAcceptCloudKitShareWith:)`) and scene-delegate
    /// (`SHIFTSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`) call
    /// only this method.
    ///
    /// The actual delivery path that fires on a real device is the scene delegate;
    /// the application-delegate method survives as defense-in-depth for legacy
    /// re-entry paths.
    @MainActor
    static func handleAcceptedShare(metadata: CKShare.Metadata) {
        if let hook = handleAcceptedShareForTesting {
            hook()
            return
        }

        let container = CKContainer(identifier: metadata.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        // Capture acceptedMetadata (first param) — its rootRecordID.zoneID lets us target
        // the exact shared zone without relying on fetchDatabaseChanges(), which can
        // return an empty list in the brief propagation window after acceptance.
        operation.perShareResultBlock = { acceptedMetadata, result in
            switch result {
            case .success:
                Self.logger.info("Successfully accepted CloudKit share in zone: \(acceptedMetadata.share.recordID.zoneID.zoneName)")
                Task { @MainActor in
                    DeepLinkRouter.shared.isAcceptingShare = true
                    DeepLinkRouter.shared.pendingDestination = .roster
                }
                // Directly fetch the specific zone we know about from the metadata.
                // This is faster and more reliable than fetchDatabaseChanges() which
                // may not yet reflect the newly accepted zone.
                let zoneID = acceptedMetadata.share.recordID.zoneID
                Task {
                    await SharedZoneSubscriptionManager.shared.fetchAllRecords(inZone: zoneID)
                }
            case .failure(let error):
                Self.logger.error("CKAcceptSharesOperation failed: \(error.localizedDescription)")
                Task { @MainActor in
                    DeepLinkRouter.shared.pendingDestination = .roster
                }
            }
        }
        operation.acceptSharesResultBlock = { result in
            if case .failure(let error) = result {
                Self.logger.error("CKAcceptSharesOperation overall failure: \(error.localizedDescription)")
            }
        }
        operation.qualityOfService = .userInteractive
        container.add(operation)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// After CloudKit sync delivers updated vendor data, scan for any
    /// `pendingShiftDelta` values and post local notifications.
    @MainActor
    private func processVendorShiftNotifications() async {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<EventModel>()
        guard let events = try? context.fetch(descriptor) else { return }

        for event in events {
            await VendorShiftLocalNotifier.processAndNotify(event: event)
        }
        try? context.save()
    }

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

    /// Show notifications even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
