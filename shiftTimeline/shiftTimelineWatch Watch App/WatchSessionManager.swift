import WatchConnectivity
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
@Observable
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

    private static let logger = Logger(
        subsystem: "com.neelsoftwaresolutions.shiftTimeline.watch",
        category: "WatchSession"
    )

    // MARK: - Init

    init(session: (any WatchSessionSending)? = nil) {
        if let session {
            self.session = session
        } else {
            self.session = WCSession.default
        }
        super.init()
    }

    // MARK: - Activation

    /// Activates the WCSession. Call once at Watch app launch.
    ///
    /// On activation, restores the last received application context so the
    /// Watch UI populates immediately even if the iPhone hasn't pushed new data.
    func activate() {
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
            currentContext = context
            Self.logger.info("Updated context from reply: \(context.activeBlockTitle)")
        }
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
                self?.currentContext = context
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
            self?.currentContext = context
            self?.isCommandQueued = false
            Self.logger.info("Received context: \(context.activeBlockTitle)")
        }
    }
}
