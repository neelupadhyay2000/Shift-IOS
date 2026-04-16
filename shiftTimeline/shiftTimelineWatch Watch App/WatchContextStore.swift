import Foundation
import Models

/// Persists `WatchContext` to a shared `UserDefaults` suite so the watchOS
/// widget extension can read complication data without a live WCSession.
///
/// Both the Watch app target and the watchOS widget extension target must
/// share the same App Group: `group.com.neelsoftwaresolutions.shiftTimeline.watch`.
enum WatchContextStore {

    static let suiteName = "group.com.neelsoftwaresolutions.shiftTimeline.watch"
    private static let contextKey = "cachedWatchContext"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// Writes the current context to the shared suite. Called by WatchSessionManager
    /// on every context update so the widget extension has fresh data.
    static func save(_ context: WatchContext) {
        guard let data = try? JSONEncoder().encode(context) else { return }
        defaults?.set(data, forKey: contextKey)
    }

    /// Reads the last-saved context. Returns `nil` if no context has been cached
    /// or if the Watch app has never received a context from the iPhone.
    static func load() -> WatchContext? {
        guard let data = defaults?.data(forKey: contextKey) else { return nil }
        return try? JSONDecoder().decode(WatchContext.self, from: data)
    }

    /// Removes the cached context (e.g. when the event is no longer live).
    static func clear() {
        defaults?.removeObject(forKey: contextKey)
    }
}
