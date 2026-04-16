import WatchConnectivity
import WatchKit
import Models
import os

// MARK: - WatchSessionSending

/// Abstraction over outgoing WCSession calls for testability.
///
/// Production code uses `WCSession.default`. Tests inject a mock.
protocol WatchSessionSending: AnyObject {
    var isReachable: Bool { get }
    var delegate: WCSessionDelegate? { get set }
    var receivedApplicationContext: [String: Any] { get }
    func activate()
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer
}

extension WCSession: WatchSessionSending {}

// MARK: - WatchSessionManager (watchOS)

/// Manages the WCSession communication bridge on the Watch side.
///
/// Responsibilities:
/// - Activates `WCSession` on app launch.
/// - Receives application context from iPhone and stores it as observable state.
/// - Sends shift and completeBlock commands to iPhone via `sendMessage`,
///   with `transferUserInfo` fallback when the iPhone is unreachable.
///
/// The Watch never accesses SwiftData or runs the RippleEngine directly.
/// All mutations are sent to the iPhone for processing.
@MainActor @Observable
final class WatchSessionManager: NSObject {

    // MARK: - Observable State (drives Watch UI)

    /// The current context received from the iPhone.
    /// `nil` until the first context arrives or is restored from the last received context.
    private(set) var currentContext: WatchContext?

    /// Set to `true` when a command was queued via `transferUserInfo`
    /// because the iPhone was unreachable.
    private(set) var isCommandQueued: Bool = false

    /// The last error from a failed `sendMessage` attempt.
    private(set) var lastError: String?

    // MARK: - Dependencies

    private let session: any WatchSessionSending

    /// Whether the session has been activated. Guards against repeated activation.
    private var didActivate = false

    // MARK: - Haptic Scheduling

    /// The end time of the block for which a haptic is currently scheduled.
    /// Used to deduplicate — if a context refresh arrives for the same block
    /// (same end time), the haptic is not rescheduled.
    private var scheduledHapticEndTime: Date?

    /// The currently running haptic timer task. Cancelled when a new block arrives.
    private var hapticTask: Task<Void, Never>?

    /// Lead time before block end at which the haptic fires.
    static let hapticLeadSeconds: TimeInterval = 5 * 60

    /// The running sunset haptic task. Cancelled if sunset time changes.
    private var sunsetHapticTask: Task<Void, Never>?

    /// Lead time before sunset at which the haptic fires.
    static let sunsetLeadSeconds: TimeInterval = 30 * 60

    /// Calendar day (yyyy-MM-dd) for which the sunset haptic has already fired.
    /// Persisted so the haptic fires only once per event day, even across app restarts.
    private var sunsetHapticFiredDay: String? {
        get { UserDefaults.standard.string(forKey: "sunsetHapticFiredDay") }
        set { UserDefaults.standard.set(newValue, forKey: "sunsetHapticFiredDay") }
    }

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline.watch",
        category: "WatchSession"
    )

    // MARK: - Init

    init(session: (any WatchSessionSending)? = nil) {
        if let session {
            self.session = session
        } else if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = NoOpWatchSession()
            Self.logger.info("WCSession not supported on this device")
        }
        super.init()
    }

    // MARK: - Activation

    /// Activates the WCSession. Call once at Watch app launch.
    ///
    /// On activation, restores the last received application context so the
    /// Watch UI populates immediately even if the iPhone hasn't pushed new data.
    /// Guarded so repeated calls (e.g. from `onAppear`) are no-ops.
    func activate() {
        guard !didActivate else { return }
        didActivate = true
        session.delegate = self
        session.activate()
        Self.logger.info("WCSession activation requested")
    }

    // MARK: - Sending Commands

    /// Sends a shift command to the iPhone.
    ///
    /// Uses `sendMessage` for real-time delivery when the iPhone is reachable.
    /// Falls back to `transferUserInfo` (queued, survives disconnection) when not.
    ///
    /// - Parameter minutes: The number of minutes to shift (positive = later).
    func sendShiftCommand(minutes: Int) {
        let command = WatchCommand(action: .shift, deltaMinutes: minutes)
        send(command)
    }

    /// Sends a "complete current block" command to the iPhone.
    func sendCompleteBlockCommand() {
        let command = WatchCommand(action: .completeBlock)
        send(command)
    }

    // MARK: - Private

    private func send(_ command: WatchCommand) {
        let message = command.toDictionary()
        isCommandQueued = false
        lastError = nil

        guard session.isReachable else {
            Self.logger.info("iPhone unreachable — queuing via transferUserInfo")
            _ = session.transferUserInfo(message)
            isCommandQueued = true
            return
        }

        session.sendMessage(
            message,
            replyHandler: { [weak self] reply in
                Task { @MainActor [weak self] in
                    self?.handleReply(reply)
                }
            },
            errorHandler: { [weak self] error in
                Self.logger.error("sendMessage failed: \(error.localizedDescription) — falling back to transferUserInfo")
                _ = self?.session.transferUserInfo(message)
                Task { @MainActor [weak self] in
                    self?.isCommandQueued = true
                    self?.lastError = error.localizedDescription
                }
            }
        )
    }

    /// Processes a reply from the iPhone containing an updated `WatchContext`.
    private func handleReply(_ reply: [String: Any]) {
        if let error = reply["error"] as? String {
            Self.logger.warning("iPhone replied with error: \(error)")
            lastError = error
            return
        }

        if let context = WatchContext(dictionary: reply) {
            applyContext(context)
            Self.logger.info("Updated context from reply: \(context.activeBlockTitle)")
        }
    }

    // MARK: - Context Application

    /// Central setter for `currentContext`. Schedules haptics whenever the context changes.
    private func applyContext(_ context: WatchContext) {
        currentContext = context
        scheduleBlockEndHaptic(for: context)
        scheduleSunsetHaptic(for: context)
    }

    // MARK: - Haptic Scheduling

    /// Schedules a `WKHapticType.notification` haptic 5 minutes before the active
    /// block's end time. Deduplicates by `activeBlockEndTime` so a context refresh
    /// for the same block does not double-fire.
    private func scheduleBlockEndHaptic(for context: WatchContext) {
        let endTime = context.activeBlockEndTime

        // Deduplicate: same block end time means same block — skip.
        if scheduledHapticEndTime == endTime { return }

        // New block or shifted block — cancel any existing timer.
        hapticTask?.cancel()
        hapticTask = nil
        scheduledHapticEndTime = endTime

        let fireDate = endTime.addingTimeInterval(-Self.hapticLeadSeconds)
        let delay = fireDate.timeIntervalSinceNow

        // If the fire date is already past, don't schedule.
        guard delay > 0 else {
            Self.logger.info("Haptic fire date already past — skipping")
            return
        }

        Self.logger.info("Scheduling block-end haptic in \(Int(delay))s")

        hapticTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fireBlockEndHaptic()
        }
    }

    private func fireBlockEndHaptic() {
        WKInterfaceDevice.current().play(.notification)
        Self.logger.info("Fired block-end haptic (5 min warning)")
    }

    // MARK: - Sunset Haptic Scheduling

    /// Schedules a `WKHapticType.directionUp` haptic 30 minutes before sunset.
    ///
    /// Deduplicates by calendar day so the haptic fires only once per event day,
    /// surviving app restarts and context refreshes within the 30-minute window.
    private func scheduleSunsetHaptic(for context: WatchContext) {
        guard let sunset = context.sunsetTime else { return }

        let dayKey = Self.calendarDayKey(for: sunset)

        // Already fired for this event day — skip entirely.
        if sunsetHapticFiredDay == dayKey { return }

        let fireDate = sunset.addingTimeInterval(-Self.sunsetLeadSeconds)
        let delay = fireDate.timeIntervalSinceNow

        // Fire date already past — mark as fired so we don't retry.
        guard delay > 0 else {
            sunsetHapticFiredDay = dayKey
            Self.logger.info("Sunset haptic fire date already past — marking as fired")
            return
        }

        // Cancel any previously scheduled sunset task (e.g. sunset time shifted).
        sunsetHapticTask?.cancel()

        Self.logger.info("Scheduling sunset haptic in \(Int(delay))s")

        sunsetHapticTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fireSunsetHaptic(dayKey: dayKey)
        }
    }

    private func fireSunsetHaptic(dayKey: String) {
        sunsetHapticFiredDay = dayKey
        WKInterfaceDevice.current().play(.directionUp)
        Self.logger.info("Fired sunset approach haptic (30 min warning)")
    }

    /// Returns a stable calendar-day string (yyyy-MM-dd) for deduplication.
    private static func calendarDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else {
            Self.logger.error("WCSession activation failed: \(error?.localizedDescription ?? "unknown")")
            return
        }

        Self.logger.info("WCSession activated")

        // Restore the last received application context immediately.
        let existing = session.receivedApplicationContext
        if !existing.isEmpty, let context = WatchContext(dictionary: existing) {
            Task { @MainActor [weak self] in
                self?.applyContext(context)
                Self.logger.info("Restored context on activation: \(context.activeBlockTitle)")
            }
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let context = WatchContext(dictionary: applicationContext) else {
            Self.logger.warning("Received unrecognized application context")
            return
        }

        Task { @MainActor [weak self] in
            self?.applyContext(context)
            self?.isCommandQueued = false
            Self.logger.info("Received context: \(context.activeBlockTitle)")
        }
    }
}

// MARK: - NoOpWatchSession

/// Stub session for simulator / unsupported devices.
private final class NoOpWatchSession: NSObject, WatchSessionSending {
    var isReachable: Bool { false }
    var delegate: WCSessionDelegate?
    var receivedApplicationContext: [String: Any] { [:] }
    func activate() {}
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {}
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer {
        fatalError("transferUserInfo called on NoOpWatchSession — WCSession is not supported")
    }
}
