import Testing
import Foundation
@testable import shiftTimeline

@Suite("SupabaseClientProvider")
@MainActor
struct SupabaseClientProviderTests {

    @Test("initializes client with provided credentials")
    func initializesWithCredentials() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        _ = provider.client
    }

    @Test("client is Sendable and accessible from a detached task")
    func clientIsAccessibleAcrossConcurrentContexts() async throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let client = provider.client  // captured on @MainActor, then sent across
        await Task.detached {
            _ = client
        }.value
    }
}
