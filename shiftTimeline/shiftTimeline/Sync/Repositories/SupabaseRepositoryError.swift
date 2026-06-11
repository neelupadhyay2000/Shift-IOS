import Foundation

/// Errors raised by the Supabase-backed repositories before a network call is
/// attempted. (Postgres/transport failures surface as the SDK's own errors and
/// are routed through sync diagnostics.)
nonisolated enum SupabaseRepositoryError: Error, Equatable {
    /// An event write was attempted with no signed-in user, so `owner_id`
    /// (required and RLS-enforced) could not be resolved.
    case notAuthenticated
}
