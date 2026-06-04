import Testing
import Foundation
@testable import shiftTimeline

@Suite("AuthState")
@MainActor
struct AuthStateTests {

    @Test("starts with no session and is unauthenticated")
    func startsUnauthenticated() {
        let state = AuthState()
        #expect(state.session == nil)
        #expect(!state.isAuthenticated)
        #expect(state.currentUser == nil)
    }

    @Test("stopListening before startListening does not crash")
    func stopListeningBeforeStartingIsIdempotent() {
        let state = AuthState()
        state.stopListening()
        #expect(state.session == nil)
    }

    @Test("startListening twice does not create a second listener")
    func startListeningIsIdempotent() async throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let state = AuthState()
        state.startListening(using: provider.client)
        state.startListening(using: provider.client)
        state.stopListening()
        #expect(state.session == nil)
    }
}
