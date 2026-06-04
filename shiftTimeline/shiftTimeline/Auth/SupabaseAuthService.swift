import Foundation
import Observation
import Supabase

/// Single auth-facing surface for the app, replacing the removed CloudKit identity.
///
/// Owns the Supabase session stream, upserts the `profiles` row on sign-in and
/// session restore, and exposes the current user's profile identity for the rest
/// of the app.
///
/// **Injection:** use `@Environment(SupabaseAuthService.self)` in views; inject
/// at the scene root via `.environment(authService)`.
@Observable
@MainActor
final class SupabaseAuthService {
    // MARK: - Observable state

    private(set) var session: Session?
    private(set) var currentProfile: ProfileDTO?

    var isAuthenticated: Bool {
        session != nil
    }

    var currentUser: User? {
        session?.user
    }

    var currentProfileID: UUID? {
        session?.user.id
    }

    // MARK: - Private deps

    @ObservationIgnored
    private var client: SupabaseClient?
    @ObservationIgnored
    private var profileRepository: (any ProfileRepositing)?
    @ObservationIgnored
    private var listenerTask: Task<Void, Never>?

    // MARK: - Init

    /// Parameterless init — safe as `@State` in the `App` struct.
    /// Wire dependencies later via `startListening(client:profileRepository:)`.
    init() {}

    /// Dependency-injected init for tests and Xcode Previews.
    init(client: SupabaseClient, profileRepository: any ProfileRepositing) {
        self.client = client
        self.profileRepository = profileRepository
    }

    // MARK: - Lifecycle

    /// Wires dependencies and begins streaming auth changes.
    /// Idempotent — subsequent calls are no-ops.
    func startListening(client: SupabaseClient, profileRepository: any ProfileRepositing) {
        guard listenerTask == nil else { return }
        self.client = client
        self.profileRepository = profileRepository
        beginListening(using: client)
    }

    func stopListening() {
        listenerTask?.cancel()
        listenerTask = nil
    }

    // MARK: - Profile upsert

    /// Upserts the `profiles` row for `user`.
    ///
    /// Pass `displayName` only on a first-time Apple sign-in — Apple delivers
    /// the user's name in the credential exactly once. For phone-OTP and
    /// returning Apple users, pass `nil` so existing Postgres values are kept.
    /// Non-fatal: sign-in succeeds even if the write fails.
    func upsertProfile(from user: User, displayName: String?) async {
        await performProfileUpsert(user: user, displayName: displayName)
    }

    // MARK: - Sign out

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut()
        // authStateChanges fires .signedOut → session and currentProfile cleared in beginListening
    }

    // MARK: - Private

    private func beginListening(using client: SupabaseClient) {
        listenerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                self.session = session
                switch event {
                case .signedIn, .initialSession:
                    if let user = session?.user {
                        await self.performProfileUpsert(user: user, displayName: nil)
                    }
                case .signedOut:
                    self.currentProfile = nil
                default:
                    break
                }
            }
        }
    }

    private func performProfileUpsert(user: User, displayName: String?) async {
        guard let repo = profileRepository else { return }
        let dto = ProfileDTO(
            id: user.id,
            displayName: displayName,
            phone: user.phone,
            email: user.email
        )
        do {
            try await repo.upsert(dto)
            currentProfile = dto
        } catch {
            // Non-fatal — SyncDiagnosticsCenter surfaces this in SHIFT-1305
        }
    }
}
