import Foundation
import os

/// A single structured diagnostic event in the share/sync funnel.
///
/// Recorded by every stage (share creation, parent-field repair, share
/// acceptance, zone fetch, record merge, silent push, vendor notification)
/// so the planner→vendor pipeline can be traced end-to-end on-device and in
/// TelemetryDeck without a cable.
public struct DiagnosticEvent: Sendable, Codable, Equatable, Identifiable {

    /// The funnel stage this event belongs to. Used to group/filter in the UI
    /// and to map to a TelemetryDeck signal in the app-layer bridge.
    public enum Category: String, Sendable, Codable, CaseIterable {
        case mirror        // CloudKit mirror health at launch
        case identity      // iCloud user record-name fetch
        case account       // CKAccountStatus
        case subscription  // shared-DB CKDatabaseSubscription
        case shareCreate   // planner creates a CKShare
        case parentRepair  // CloudKit parent-field patching
        case shareAccept   // vendor accepts a CKShare
        case fetch         // shared-DB change fetch
        case merge         // record import into SwiftData
        case push          // silent push / foreground poll tick
        case notify        // vendor shift local notification
    }

    public enum Severity: String, Sendable, Codable {
        case info
        case warning
        case error
    }

    public let id: UUID
    public let timestamp: Date
    public let category: Category
    public let name: String
    public let params: [String: String]
    public let severity: Severity

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: Category,
        name: String,
        params: [String: String] = [:],
        severity: Severity = .info
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.name = name
        self.params = params
        self.severity = severity
    }
}

/// Single source of truth for share/sync diagnostics.
///
/// Holds a capped, newest-first ring buffer of `DiagnosticEvent`s, persisted to
/// the App Group `UserDefaults` so the log survives relaunch and is readable on
/// the device. The in-app `SyncDiagnosticsView` renders `events`; the app-layer
/// bridge forwards each new event to TelemetryDeck.
///
/// Deliberately a lock-backed plain class rather than `@Observable`: `record`
/// is called from background threads off the main actor, and the diagnostics
/// screen refreshes on a timer, so we avoid data races of mutating an
/// `@Observable` property off-main.
public final class SyncDiagnosticsCenter: @unchecked Sendable {

    public static let shared = SyncDiagnosticsCenter()

    private static let appGroupID = "group.com.neelsoftwaresolutions.shiftTimeline"

    /// Default `UserDefaults` storage key. `public` so it can be referenced from
    /// the `public init`'s default argument.
    public static let defaultStorageKey = "com.shift.syncDiagnostics.events"

    /// App Group defaults when available (shared with extensions), else standard.
    /// `public` so it can be referenced from the `public init`'s default argument.
    public static var defaultDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static let logger = Logger(subsystem: "com.shift.diagnostics", category: "SyncDiagnostics")

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxEvents: Int

    private let lock = NSLock()
    private var storage: [DiagnosticEvent]   // newest-first

    private let observerLock = NSLock()
    private var observers: [@Sendable (DiagnosticEvent) -> Void] = []

    public init(
        defaults: UserDefaults = SyncDiagnosticsCenter.defaultDefaults,
        storageKey: String = SyncDiagnosticsCenter.defaultStorageKey,
        maxEvents: Int = 500
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maxEvents = max(1, maxEvents)
        self.storage = Self.load(from: defaults, key: storageKey)
    }

    // MARK: - Observers

    /// Registers a sink notified on every `record`. The app uses this to
    /// forward events to TelemetryDeck without SHIFTKit importing TelemetryDeck.
    /// Observers are invoked outside the storage lock, on the recording thread.
    public func addObserver(_ observer: @escaping @Sendable (DiagnosticEvent) -> Void) {
        observerLock.lock()
        observers.append(observer)
        observerLock.unlock()
    }

    // MARK: - Reads

    /// A thread-safe snapshot of recorded events, newest-first.
    public var events: [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    // MARK: - Writes

    /// Records a diagnostic event. Safe to call from any thread.
    public func record(
        _ category: DiagnosticEvent.Category,
        _ name: String,
        params: [String: String] = [:],
        severity: DiagnosticEvent.Severity = .info
    ) {
        let event = DiagnosticEvent(
            category: category,
            name: name,
            params: params,
            severity: severity
        )

        lock.lock()
        storage.insert(event, at: 0)
        if storage.count > maxEvents {
            storage.removeLast(storage.count - maxEvents)
        }
        let snapshot = storage
        lock.unlock()

        persist(snapshot)

        // Mirror to the unified log so it also shows up in Console.app captures.
        Self.logger.log(
            level: severity.osLogType,
            "\(category.rawValue, privacy: .public).\(name, privacy: .public) \(Self.describe(params), privacy: .public)"
        )

        // Notify observers (e.g. the app's TelemetryDeck bridge) outside the lock.
        observerLock.lock()
        let sinks = observers
        observerLock.unlock()
        for sink in sinks { sink(event) }
    }

    /// Removes all events from memory and the persisted store.
    public func clear() {
        lock.lock()
        storage = []
        lock.unlock()
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: - Export

    /// A flat, copy-pasteable text dump of every event, newest-first.
    /// Backs the "Copy Diagnostics" button so findings can be shared without a cable.
    public func exportText() -> String {
        let snapshot = events
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let header = "SHIFT Sync Diagnostics — \(snapshot.count) event(s)\n"
        let lines = snapshot.map { event -> String in
            let time = formatter.string(from: event.timestamp)
            let params = event.params.isEmpty ? "" : " \(Self.describe(event.params))"
            return "[\(time)] [\(event.severity.rawValue)] \(event.category.rawValue).\(event.name)\(params)"
        }
        return header + lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func persist(_ snapshot: [DiagnosticEvent]) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [DiagnosticEvent] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - Helpers

    private static func describe(_ params: [String: String]) -> String {
        guard !params.isEmpty else { return "{}" }
        let body = params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        return "{\(body)}"
    }
}

private extension DiagnosticEvent.Severity {
    var osLogType: OSLogType {
        switch self {
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}
