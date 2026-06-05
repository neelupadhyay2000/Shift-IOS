import Supabase

/// One realtime row change for a specific table, normalized from the Supabase
/// `AnyAction`.
///
/// INSERT and UPDATE both become `upsert` (apply the new `record`); DELETE
/// carries the `oldRecord` (its primary-key columns). Carrying the raw
/// `JSONObject` — rather than the SDK's `AnyAction` — keeps the apply layer
/// (SHIFT-597) decode-driven and unit-testable. The `record` is decoded into a
/// DTO and applied to SwiftData on the main actor.
nonisolated enum RealtimeChange {
    case upsert(table: String, record: JSONObject)
    case delete(table: String, oldRecord: JSONObject)

    /// The affected table.
    var table: String {
        switch self {
        case let .upsert(table, _): return table
        case let .delete(table, _): return table
        }
    }
}
