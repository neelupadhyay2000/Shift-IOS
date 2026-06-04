import Foundation
import Observation
import Supabase

/// Observable auth session state. Drives all sign-in gating in the UI.
///
/// On `startListening(using:)` the supabase-swift client replays the session
/// persisted in the Keychain (`.initialSession` event) before streaming any
/// subsequent sign-in / sign-out / token-refresh events. Token refresh is
/// handled automatically by `SupabaseClient`; no manual timer needed.
@Observable
@MainActor
final class AuthState {

    private(set) var session: Session?

    var isAuthenticated: Bool { session != nil }
    var currentUser: User? { session?.user }

    @ObservationIgnored
    private var listenerTask: Task<Void, Never>?

    /// Begins streaming auth changes. Idempotent — subsequent calls are no-ops.
    func startListening(using client: SupabaseClient) {
        guard listenerTask == nil else { return }
        listenerTask = Task { @MainActor [weak self] in
            for await (_, session) in await client.auth.authStateChanges {
                self?.session = session
            }
        }
    }

    func stopListening() {
        listenerTask?.cancel()
        listenerTask = nil
    }
}
