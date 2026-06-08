/// Compile-time feature gates. Flip to `true` when the feature lands.
enum FeatureFlags {
    /// Master switch for the entire Supabase data layer — vendor sharing,
    /// per-event realtime, the Outbox write/flush sync path, initial hydration,
    /// delta reconciliation, and the one-time backfill (the E16 cutover,
    /// SHIFT-658). `true` by default (sharing already shipped on); retained as an
    /// emergency kill switch that drops the app back to fully-local, single-user
    /// behaviour. Replaces the transitional `vendorSharing` flag from E14 — there
    /// is intentionally only one flag now, no half-on states.
    static let supabaseSync = true

    /// Phone OTP sign-in. Off until an SMS provider (e.g. Twilio) is configured
    /// in Supabase Auth — without one the OTP request hangs. Sign in with Apple
    /// is the active path. Flip to `true` once a provider is wired up.
    static let phoneSignIn = false
}
