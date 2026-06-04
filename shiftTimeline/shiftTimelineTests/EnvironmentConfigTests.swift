import Testing
import Foundation

@Suite("Environment Configuration")
struct EnvironmentConfigTests {

    @Test("SUPABASE_REF is a non-empty Supabase project reference ID")
    func supabaseRefIsPresent() throws {
        let ref = try #require(Bundle.main.infoDictionary?["SUPABASE_REF"] as? String)
        #expect(!ref.isEmpty)
    }

    @Test("SUPABASE_REF constructs a valid HTTPS supabase.co URL")
    func supabaseRefBuildsValidURL() throws {
        let ref = try #require(Bundle.main.infoDictionary?["SUPABASE_REF"] as? String)
        let url = try #require(URL(string: "https://\(ref).supabase.co"))
        #expect(url.scheme == "https")
        #expect(url.host?.hasSuffix(".supabase.co") == true)
    }

    @Test("SUPABASE_ANON_KEY is non-empty")
    func supabaseAnonKeyIsPresent() throws {
        let key = try #require(Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String)
        #expect(!key.isEmpty)
    }

    #if DEBUG
    @Test("debug builds target the dev Supabase project")
    func debugBuildsUseDevProject() throws {
        let ref = try #require(Bundle.main.infoDictionary?["SUPABASE_REF"] as? String)
        #expect(ref == "wrhrpyinkcopqsibmkrf")
    }
    #endif
}
