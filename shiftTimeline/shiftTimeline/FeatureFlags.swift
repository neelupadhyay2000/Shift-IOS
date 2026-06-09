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

    /// Phone OTP sign-in. Off — requires a verified SMS provider (Twilio A2P etc.)
    /// in Supabase Auth, which needs business/ID verification. Email OTP +
    /// link-based invite claim cover vendor onboarding without SMS; flip this on
    /// only if/when a verified SMS sender is in place.
    static let phoneSignIn = false

    /// Email OTP sign-in (6-digit code). ON as of 2026-06-08 — Resend SMTP
    /// (`shifttimeline.app`) configured in Supabase Auth and the Magic Link
    /// template set to send the code (`{{ .Token }}`). Retained as a kill switch.
    static let emailSignIn = true
}
