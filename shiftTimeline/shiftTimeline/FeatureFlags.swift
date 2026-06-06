/// Compile-time feature gates. Flip to `true` when the feature lands.
enum FeatureFlags {
    /// Vendor sharing via Supabase. Live as of E14 (SHIFT-624); retained as a
    /// kill switch.
    static let vendorSharing = true
}
