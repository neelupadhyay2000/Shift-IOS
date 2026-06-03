import Foundation

/// Tracks shared events a vendor has chosen to remove from their own device.
///
/// A vendor's local copy of a shared event is re-created by `SharedRecordSyncer`
/// whenever the planner next touches the record, so a plain local delete would
/// resurrect on the following sync. Recording the event's `id` here makes the
/// removal stick: the syncer skips dismissed ids, and the roster filters them
/// out. The planner re-inviting (or the event being purged) is unaffected — this
/// only suppresses re-creation of records the vendor explicitly dismissed.
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
