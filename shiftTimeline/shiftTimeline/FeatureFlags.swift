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

    /// Phone OTP sign-in. **ON everywhere as of 2026-07-09.**
    ///
    /// Was DEBUG-only while SMS delivery was unproven: Twilio A2P 10DLC was in
    /// carrier review, so a Release build would have shown a phone button whose
    /// code could never arrive. Resolved by moving to **Twilio Verify**, which
    /// delivers OTPs without a 10DLC campaign.
    ///
    /// Verified against both projects' `/auth/v1/settings` before flipping:
    ///   dev  → "phone": true, "sms_provider": "twilio_verify"
    ///   prod → "phone": true, "sms_provider": "twilio_verify"
    ///
    /// Phone-only accounts have no email, so `CompleteProfileView` collects one
    /// after sign-in (`SupabaseAuthService.needsProfileCompletion`), and
    /// `AuthMethodStore.last` routes forgot-passcode back to the phone screen.
    ///
    /// Retained as a kill switch: set to `false` and ship a hotfix if SMS delivery
    /// degrades — email OTP keeps every existing account reachable.
    static let phoneSignIn = true

    /// Email OTP sign-in (6-digit code). ON as of 2026-06-08 — Resend SMTP
    /// (`shifttimeline.app`) configured in Supabase Auth and the Magic Link
    /// template set to send the code (`{{ .Token }}`). Retained as a kill switch.
    static let emailSignIn = true
}
