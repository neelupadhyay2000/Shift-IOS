import Foundation

/// Tracks shared events a vendor has chosen to remove from their own device.
///
/// Recording the event's `id` here prevents the roster from re-showing dismissed
/// events if they are re-synced. The planner re-inviting (or the event being
/// purged) is unaffected — this only suppresses re-creation of records the
/// vendor explicitly dismissed.
public enum SharedEventDismissalStore {

    private static let key = "com.shift.dismissedSharedEventIDs"

    /// Marks a shared event as dismissed on this device.
    public static func dismiss(_ id: UUID) {
        var ids = rawIDs()
        ids.insert(id.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    /// Clears a dismissal (e.g. if the vendor is re-invited and accepts again).
    public static func restore(_ id: UUID) {
        var ids = rawIDs()
        guard ids.remove(id.uuidString) != nil else { return }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    public static func isDismissed(_ id: UUID) -> Bool {
        rawIDs().contains(id.uuidString)
    }

    public static func dismissedIDs() -> Set<UUID> {
        Set(rawIDs().compactMap(UUID.init))
    }

    private static func rawIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}
