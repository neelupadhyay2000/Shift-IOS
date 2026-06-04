import Foundation
import Supabase

/// Vends the single configured `SupabaseClient` for the app.
///
/// Credentials are read from Info.plist entries `SUPABASE_URL` and `SUPABASE_ANON_KEY`,
/// populated by `Secrets.xcconfig` at build time. SHIFT-574 will wire separate
/// Debug/Release xcconfig files so dev and prod projects are selected automatically.
@MainActor
final class SupabaseClientProvider {

    /// Shared instance initialized from main-bundle Info.plist.
    ///
    /// `SUPABASE_REF` is the bare Supabase project reference ID (no slashes) so
    /// xcconfig comment-stripping of `//` doesn't corrupt the value.
    /// The full URL is constructed here as `https://<ref>.supabase.co`.
    static let shared: SupabaseClientProvider = {
        guard
            let ref = Bundle.main.infoDictionary?["SUPABASE_REF"] as? String,
            !ref.isEmpty,
            let url = URL(string: "https://\(ref).supabase.co"),
            let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
            !key.isEmpty
        else {
            fatalError("Info.plist must define SUPABASE_REF and SUPABASE_ANON_KEY via Config/Debug.xcconfig or Config/Release.xcconfig")
        }
        return SupabaseClientProvider(supabaseURL: url, supabaseKey: key)
    }()

    let client: SupabaseClient

    init(supabaseURL: URL, supabaseKey: String) {
        // supabase-swift 2.x defaults on Apple platforms:
        //   storage       → KeychainLocalStorage  (session survives relaunch)
        //   autoRefreshToken → true               (tokens refresh silently before expiry)
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }
}
