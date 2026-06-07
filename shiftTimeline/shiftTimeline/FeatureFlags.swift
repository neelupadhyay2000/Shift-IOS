/// Compile-time feature gates. Flip to `true` when the feature lands.
enum FeatureFlags {
    /// Vendor sharing via Supabase. Live as of E14 (SHIFT-624); retained as a
    /// kill switch.
    static let vendorSharing = true

    /// Phone OTP sign-in. Off until an SMS provider (e.g. Twilio) is configured
    /// in Supabase Auth — without one the OTP request hangs. Sign in with Apple
    /// is the active path. Flip to `true` once a provider is wired up.
    static let phoneSignIn = false
}
