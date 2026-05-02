import WatchConnectivity
import SwiftData
import Models
import Engine
import Services
import os

// MARK: - WatchSessionProtocol

/// Abstraction over `WCSession` for testability.
///
/// Production code uses `WCSession.default`. Tests inject a mock that
/// captures sent contexts and messages without requiring a paired Watch.
public protocol WatchSessionProtocol: AnyObject {
    var isReachable: Bool { get }
    var delegate: WCSessionDelegate? { get set }
    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )
}

extension WCSession: WatchSessionProtocol {}

// MARK: - WatchSessionManager

/// Manages the WCSession communication bridge between the iPhone and
/// the paired Apple Watch.
///
/// Responsibilities:
/// - Activates `WCSession` on app launch.
/// - Pushes the current active block context to Watch on session activation
///   and whenever timeline state changes.
/// - Receives real-time shift commands from Watch via `didReceiveMessage`.
/// - Receives background context updates via `didReceiveApplicationContext`.
///
/// This class is `@MainActor` because it reads/writes SwiftData models
/// (which are main-actor-isolated) and drives observable UI state.
@MainActor @Observable
public final class WatchSessionManager {

    // MARK: - Observable State

    /// The most recent context sent to the Watch, for UI inspection/debugging.
    public private(set) var lastSentContext: WatchContext?

    /// The most recent command received from the Watch.
    public internal(set) var lastReceivedCommand: WatchCommand?

    /// Whether the session has been activated. Guards against repeated activation.
    private var didActivate = false

    // MARK: - Dependencies

    private let session: any WatchSessionProtocol
    private let container: ModelContainer
    private let engine: RippleEngine
    private let delegate: SessionDelegate

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline",
        category: "WatchSession"
    )

    // MARK: - Init

    public init(
        session: (any WatchSessionProtocol)? = nil,
        container: ModelContainer? = nil,
        engine: RippleEngine = RippleEngine()
    ) {
        let resolvedSession: any WatchSessionProtocol
        if let session {
            resolvedSession = session
        } else if WCSession.isSupported() {
            resolvedSession = WCSession.default
        } else {
            // Simulator or unsupported device — use a no-op session.
            resolvedSession = NoOpWatchSession()
            Self.logger.info("WCSession not supported on this device")
        }

        self.session = resolvedSession
        self.container = container ?? PersistenceController.shared.container
        self.engine = engine
        self.delegate = SessionDelegate()

        self.delegate.manager = self
    }

    // MARK: - Activation

    /// Activates the WCSession. Call once at app launch.
    ///
    /// On successful activation, the delegate's `activationDidComplete`
    /// callback pushes the current live event context to the Watch.
    /// Guarded so repeated calls (e.g. from `onAppear`) are no-ops.
    public func activate() {
        guard !didActivate else { return }
        didActivate = true
        session.delegate = delegate
        session.activate()
        Self.logger.info("WCSession activation requested")
    }

    // MARK: - Sending Context

    /// Pushes the current live-event context to the Watch via `WCSession.default`.
    ///
    /// Safe to call from contexts without a long-lived manager (e.g. AppIntents).
    /// Uses the shared `PersistenceController` container and `WCSession.default`.
    /// No-op if WCSession is unsupported or no live event exists.
    public static func pushCurrentContext() {
        guard WCSession.isSupported() else { return }
        let container = PersistenceController.shared.container
        let modelContext = container.mainContext
        let descriptor = FetchDescriptor<EventModel>()
        guard let events = try? modelContext.fetch(descriptor),
              let event = events.first(where: { $0.status == .live }) else {
            return
        }

        let blocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        guard let activeBlock = blocks.first(where: { $0.status == .active }) else { return }

        let nextBlock: TimeBlockModel? = {
            guard let idx = blocks.firstIndex(where: { $0.id == activeBlock.id }) else { return nil }
            return blocks.suffix(from: blocks.index(after: idx))
                .first(where: { $0.status != .completed })
        }()

        let context = WatchContext(
            eventID: event.id,
            eventTitle: event.title,
            activeBlockTitle: activeBlock.title,
            activeBlockEndTime: activeBlock.scheduledStart.addingTimeInterval(activeBlock.duration),
            nextBlockTitle: nextBlock?.title,
            nextBlockStartTime: nextBlock?.scheduledStart,
            sunsetTime: event.sunsetTime,
            isLive: true
        )

        try? WCSession.default.updateApplicationContext(context.toDictionary())
        logger.info("Pushed Watch context (static): \(context.activeBlockTitle)")
    }

    /// Pushes the current active block data to the Watch.
    ///
    /// Call this:
    /// - On session activation (automatic)
    /// - When going live
    /// - On every block advance
    /// - After a shift is committed
    ///
    /// No-op if there is no live event or no active block.
    public func sendCurrentContext() {
        guard let context = buildCurrentContext() else {
            Self.logger.info("No live event — skipping Watch context send")
            return
        }

        do {
            try session.updateApplicationContext(context.toDictionary())
            lastSentContext = context
            Self.logger.info("Sent Watch context: \(context.activeBlockTitle)")
        } catch {
            Self.logger.error("Failed to send Watch context: \(error.localizedDescription)")
        }
    }

    /// Builds a `WatchContext` for a specific event and blocks.
    /// Useful when the caller already has the relevant models in scope.
    public func sendContext(
        for event: EventModel,
        activeBlock: TimeBlockModel,
        nextBlock: TimeBlockModel?
    ) {
        let context = WatchContext(
            eventID: event.id,
            eventTitle: event.title,
            activeBlockTitle: activeBlock.title,
            activeBlockEndTime: activeBlock.scheduledStart.addingTimeInterval(activeBlock.duration),
            nextBlockTitle: nextBlock?.title,
            nextBlockStartTime: nextBlock?.scheduledStart,
            sunsetTime: event.sunsetTime,
            isLive: event.status == .live
        )

        do {
            try session.updateApplicationContext(context.toDictionary())
            lastSentContext = context
            Self.logger.info("Sent Watch context: \(context.activeBlockTitle)")
        } catch {
            Self.logger.error("Failed to send Watch context: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal Handlers

    /// Called by the delegate when a real-time message arrives from the Watch.
    func handleMessage(
        _ message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = WatchCommand(dictionary: message) else {
            Self.logger.warning("Received unrecognized Watch message: \(message.keys.joined(separator: ", "))")
            replyHandler(["error": "unrecognized_command"])
            return
        }

        lastReceivedCommand = command
        Self.logger.info("Received Watch command: \(command.action.rawValue)")

        switch command.action {
        case .shift:
            handleShiftCommand(deltaMinutes: command.deltaMinutes ?? 0, replyHandler: replyHandler)
        case .completeBlock:
            handleCompleteBlockCommand(replyHandler: replyHandler)
        }
    }

    /// Called by the delegate when background context arrives from the Watch.
    func handleReceivedApplicationContext(_ context: [String: Any]) {
        // The Watch does not normally send application context to the iPhone,
        // but we handle it defensively for forward compatibility.
        Self.logger.info("Received application context from Watch: \(context.keys.joined(separator: ", "))")
    }

    /// Called by the delegate when a queued command arrives via `transferUserInfo`.
    ///
    /// Processes the command identically to `handleMessage`, but without a
    /// reply handler. Pushes updated context via `sendCurrentContext()` once.
    func handleQueuedCommand(_ userInfo: [String: Any]) {
        guard let command = WatchCommand(dictionary: userInfo) else {
            Self.logger.warning("Received unrecognized queued userInfo: \(userInfo.keys.joined(separator: ", "))")
            return
        }

        lastReceivedCommand = command
        Self.logger.info("Processing queued command: \(command.action.rawValue)")

        // Use a no-op reply handler — transferUserInfo has no reply path.
        handleMessage(userInfo) { _ in }

        // Push the latest context to the Watch after processing.
        sendCurrentContext()
    }

    /// Called by the delegate when the session activates successfully.
    func handleActivationComplete() {
        Self.logger.info("WCSession activated — sending current context")
        sendCurrentContext()
    }

    // MARK: - Command Processing

    private func handleShiftCommand(
        deltaMinutes: Int,
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard deltaMinutes != 0 else {
            replyHandler(["error": "zero_delta"])
            return
        }

        let modelContext = container.mainContext

        guard let event = fetchLiveEvent(context: modelContext) else {
            replyHandler(["error": "no_live_event"])
            return
        }

        let blocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        guard let activeBlock = blocks.first(where: { $0.status == .active }) else {
            replyHandler(["error": "no_active_block"])
            return
        }

        let delta = TimeInterval(deltaMinutes * 60)
        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: activeBlock.id,
            delta: delta
        )

        switch result.status {
        case .pinnedBlockCannotShift, .circularDependency:
            replyHandler(["error": result.status.rawValue])
            return
        case .clean, .hasCollisions, .impossible:
            break
        }

        VendorShiftNotifier.applyThresholdNotifications(
            event: event,
            blocks: result.blocks
        )

        PersistenceController.recordShift(
            deltaMinutes: deltaMinutes,
            triggeredBy: .watch,
            sourceBlock: activeBlock,
            event: event,
            into: modelContext
        )

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save shift: \(error.localizedDescription)")
            replyHandler(["error": "save_failed"])
            return
        }

        // Re-derive active/next after the shift and reply with updated context.
        let updatedActive = blocks.first(where: { $0.status == .active })
        let updatedNext: TimeBlockModel? = {
            guard let active = updatedActive,
                  let idx = blocks.firstIndex(where: { $0.id == active.id }) else {
                return nil
            }
            return blocks.suffix(from: blocks.index(after: idx))
                .first(where: { $0.status != .completed })
        }()

        if let updatedActive {
            let replyContext = WatchContext(
                eventID: event.id,
                eventTitle: event.title,
                activeBlockTitle: updatedActive.title,
                activeBlockEndTime: updatedActive.scheduledStart.addingTimeInterval(updatedActive.duration),
                nextBlockTitle: updatedNext?.title,
                nextBlockStartTime: updatedNext?.scheduledStart,
                sunsetTime: event.sunsetTime,
                isLive: true
            )
            replyHandler(replyContext.toDictionary())
            lastSentContext = replyContext

            // Also push via applicationContext for Watch's background state.
            try? session.updateApplicationContext(replyContext.toDictionary())
        } else {
            replyHandler(["error": "no_active_block_after_shift"])
        }
    }

    private func handleCompleteBlockCommand(
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let modelContext = container.mainContext

        guard let event = fetchLiveEvent(context: modelContext) else {
            replyHandler(["error": "no_live_event"])
            return
        }

        let blocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        guard let activeBlock = blocks.first(where: { $0.status == .active }) else {
            replyHandler(["error": "no_active_block"])
            return
        }

        // Advance: complete current, activate next.
        activeBlock.status = .completed
        // Stamp wall-clock completion so the post-event report can
        // compare planned vs. actual for this block.
        activeBlock.completedTime = Date()
        let nextBlock = blocks
            .drop(while: { $0.id != activeBlock.id })
            .dropFirst()
            .first(where: { $0.status != .completed })

        if let nextBlock {
            nextBlock.status = .active
        } else {
            event.status = .completed
            // Final block — build the post-event report now so the
            // iPhone UI sees a populated `event.postEventReport` the
            // moment the watch save propagates back.
            PostEventReportGenerator.generate(for: event)
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save block advance: \(error.localizedDescription)")
            replyHandler(["error": "save_failed"])
            return
        }

        // Build reply with updated state.
        let replyActive = nextBlock ?? activeBlock
        let replyNext: TimeBlockModel? = {
            guard let next = nextBlock,
                  let idx = blocks.firstIndex(where: { $0.id == next.id }) else {
                return nil
            }
            return blocks.suffix(from: blocks.index(after: idx))
                .first(where: { $0.status != .completed })
        }()

        let replyContext = WatchContext(
            eventID: event.id,
            eventTitle: event.title,
            activeBlockTitle: replyActive.title,
            activeBlockEndTime: replyActive.scheduledStart.addingTimeInterval(replyActive.duration),
            nextBlockTitle: replyNext?.title,
            nextBlockStartTime: replyNext?.scheduledStart,
            sunsetTime: event.sunsetTime,
            isLive: event.status == .live
        )
        replyHandler(replyContext.toDictionary())
        lastSentContext = replyContext
        try? session.updateApplicationContext(replyContext.toDictionary())
    }

    // MARK: - Helpers

    private func buildCurrentContext() -> WatchContext? {
        let modelContext = container.mainContext
        guard let event = fetchLiveEvent(context: modelContext) else { return nil }

        let blocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        guard let activeBlock = blocks.first(where: { $0.status == .active }) else { return nil }

        let nextBlock: TimeBlockModel? = {
            guard let idx = blocks.firstIndex(where: { $0.id == activeBlock.id }) else {
                return nil
            }
            return blocks.suffix(from: blocks.index(after: idx))
                .first(where: { $0.status != .completed })
        }()

        return WatchContext(
            eventID: event.id,
            eventTitle: event.title,
            activeBlockTitle: activeBlock.title,
            activeBlockEndTime: activeBlock.scheduledStart.addingTimeInterval(activeBlock.duration),
            nextBlockTitle: nextBlock?.title,
            nextBlockStartTime: nextBlock?.scheduledStart,
            sunsetTime: event.sunsetTime,
            isLive: true
        )
    }

    private func fetchLiveEvent(context: ModelContext) -> EventModel? {
        let descriptor = FetchDescriptor<EventModel>()
        guard let events = try? context.fetch(descriptor) else { return nil }
        return events.first(where: { $0.status == .live })
    }
}

// MARK: - SessionDelegate

/// WCSessionDelegate bridge that forwards calls to the `@MainActor` manager.
///
/// WCSession requires its delegate to be an `NSObject` subclass. This thin
/// bridge dispatches to `WatchSessionManager` on `@MainActor`.
private final class SessionDelegate: NSObject, WCSessionDelegate {

    /// Weak-ish back-reference. Set immediately after init, before activation.
    /// Accessed only from MainActor dispatch blocks.
    weak var manager: WatchSessionManager?

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            self?.manager?.handleActivationComplete()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Required on iOS. No action needed.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for Watch switching scenarios.
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.manager?.handleMessage(message, replyHandler: replyHandler)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.manager?.handleReceivedApplicationContext(applicationContext)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor [weak self] in
            self?.manager?.handleQueuedCommand(userInfo)
        }
    }
}

// MARK: - NoOpWatchSession

/// Stub session for simulator / unsupported devices.
final class NoOpWatchSession: WatchSessionProtocol {
    var isReachable: Bool { false }
    var delegate: WCSessionDelegate?
    func activate() {}
    func updateApplicationContext(_ applicationContext: [String: Any]) throws {}
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {}
}
