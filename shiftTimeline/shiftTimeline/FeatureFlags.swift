/// Compile-time feature gates. Flip to `true` when the feature lands.
enum FeatureFlags {
    /// Master switch for the entire Supabase data layer — vendor sharing,
    /// per-event realtime, the Outbox write/flush sync path, initial hydration,
    /// delta reconciliation, and the one-time backfill.
    /// `true` by default (sharing already shipped on); retained as an
    /// emergency kill switch that drops the app back to fully-local, single-user
    /// behaviour. Replaces the earlier transitional `vendorSharing` flag — there
    /// is intentionally only one flag now, no half-on states.
    static let supabaseSync = true

    /// Phone OTP sign-in. DEBUG-only (2026-06-21): on when run from Xcode for
    /// dev/test against Supabase test numbers, but OFF in Release/TestFlight/App
    /// Store so real users never see a phone button whose SMS can't yet deliver
    /// (Twilio A2P 10DLC for the SHIFT-OTP service is still in carrier review).
    /// To launch for real: confirm prod Supabase Phone provider + approved 10DLC,
    /// then make this an unconditional `true`.
    #if DEBUG
    static let phoneSignIn = true
    #else
    static let phoneSignIn = false
    #endif

    /// Email OTP sign-in (6-digit code). ON as of 2026-06-08 — Resend SMTP
    /// (`shifttimeline.app`) configured in Supabase Auth and the Magic Link
    /// template set to send the code (`{{ .Token }}`). Retained as a kill switch.
    static let emailSignIn = true
}
