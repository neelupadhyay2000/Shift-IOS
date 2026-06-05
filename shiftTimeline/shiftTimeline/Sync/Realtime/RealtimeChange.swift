import Supabase

/// One realtime row change for a specific table, as delivered by Supabase
/// Realtime over an event's channel.
///
/// `action` is `.insert` / `.update` / `.delete`; the row payload lives on it
/// (`record` for insert/update, `oldRecord` for delete). SHIFT-597 decodes that
/// payload into a DTO and applies it to SwiftData on the main actor.
nonisolated struct RealtimeChange {
    let table: String
    let action: AnyAction
}
