import Foundation
import Models
import Observation
import Services
import Supabase
import SwiftData

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
    /// The signed-in user's `profiles` row. Setting it forwards the
    /// server-granted comp window to `SubscriptionManager`, so sign-in
    /// applies a grant and sign-out / account deletion revokes it.
    private(set) var currentProfile: ProfileDTO? {
        didSet { SubscriptionManager.shared.compedUntil = currentProfile?.compedUntil?.value }
    }

    /// `true` once the SDK has emitted its initial (stored) session on launch.
    /// The auth gate shows a loading state until this flips, so a returning user
    /// never sees a flash of the sign-in screen before the session restores.
    private(set) var hasResolvedInitialSession = false

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
    private var inviteClaimer: (any InviteClaiming)?
    @ObservationIgnored
    private var deviceTokenRegistrar: DeviceTokenRegistrar?
    @ObservationIgnored
    private var dataBackfiller: (any DataBackfilling)?
    @ObservationIgnored
    private var sessionSync: (any SessionSyncing)?
    @ObservationIgnored
    private var modelContext: ModelContext?
    @ObservationIgnored
    private var listenerTask: Task<Void, Never>?

    // MARK: - Init

    /// Parameterless init — safe as `@State` in the `App` struct.
    /// Wire dependencies later via `startListening(client:profileRepository:modelContext:)`.
    init() {}

    /// Dependency-injected init for tests and Xcode Previews.
    /// `modelContext` is optional — omit it when testing behaviour that doesn't
    /// involve cache clearing. `inviteClaimer` is optional — omit it when the
    /// claim-on-sign-in path is not under test.
    init(
        client: SupabaseClient,
        profileRepository: any ProfileRepositing,
        inviteClaimer: (any InviteClaiming)? = nil,
        deviceTokenRegistrar: DeviceTokenRegistrar? = nil,
        dataBackfiller: (any DataBackfilling)? = nil,
        sessionSync: (any SessionSyncing)? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.profileRepository = profileRepository
        self.inviteClaimer = inviteClaimer
        self.deviceTokenRegistrar = deviceTokenRegistrar
        self.dataBackfiller = dataBackfiller
        self.sessionSync = sessionSync
        self.modelContext = modelContext
    }

    // MARK: - Lifecycle

    /// Wires all dependencies and begins streaming auth changes.
    /// Idempotent — subsequent calls are no-ops.
    func startListening(
        client: SupabaseClient,
        profileRepository: any ProfileRepositing,
        inviteClaimer: (any InviteClaiming)? = nil,
        deviceTokenRegistrar: DeviceTokenRegistrar? = nil,
        dataBackfiller: (any DataBackfilling)? = nil,
        sessionSync: (any SessionSyncing)? = nil,
        modelContext: ModelContext? = nil
    ) {
        guard listenerTask == nil else { return }
        self.client = client
        self.profileRepository = profileRepository
        self.inviteClaimer = inviteClaimer
        self.deviceTokenRegistrar = deviceTokenRegistrar
        self.dataBackfiller = dataBackfiller
        self.sessionSync = sessionSync
        self.modelContext = modelContext
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
    /// returning Apple users pass `nil` so existing Postgres values are kept.
    /// Non-fatal: sign-in succeeds even if the write fails.
    func upsertProfile(from user: User, displayName: String?) async {
        await performProfileUpsert(user: user, displayName: displayName)
    }

    // MARK: - Invite claim

    /// Runs the authoritative server-side invite claim (`claim_invite` RPC) and
    /// returns the `event_vendors` rows the server linked to this identity.
    ///
    /// The match is performed server-side against the verified `auth.users`
    /// identity, so the client cannot claim an invite that wasn't addressed to
    /// it. Non-fatal: sign-in proceeds even if the claim fails. A no-op when no
    /// `inviteClaimer` is injected (e.g. in tests that don't exercise claiming).
    @discardableResult
    func claimPendingInvites() async -> [EventVendorDTO] {
        guard let inviteClaimer else { return [] }
        do {
            let claimed = try await inviteClaimer.claimInvites()
            if !claimed.isEmpty {
                SyncDiagnosticsCenter.shared.record(
                    .auth, "invitesClaimed",
                    params: ["count": String(claimed.count)]
                )
            }
            return claimed
        } catch {
            SyncDiagnosticsCenter.shared.record(
                .auth, "inviteClaimFailed",
                params: ["error": String(describing: error)],
                severity: .error
            )
            return []
        }
    }

    /// Possession-based claim for a tapped invite link (`claim_invite_by_id`).
    /// Claims the one `event_vendors` row the link points to, regardless of
    /// whether the invite's phone/email matches this identity — so a phone
    /// invite is claimable via email OTP. Non-fatal; a no-op without a claimer.
    @discardableResult
    func claimInvite(vendorID: UUID) async -> [EventVendorDTO] {
        guard let inviteClaimer else { return [] }
        do {
            let claimed = try await inviteClaimer.claimInvite(vendorID: vendorID)
            if !claimed.isEmpty {
                SyncDiagnosticsCenter.shared.record(
                    .auth, "inviteClaimedByLink",
                    params: ["count": String(claimed.count), "vendor": vendorID.uuidString]
                )
            }
            return claimed
        } catch {
            SyncDiagnosticsCenter.shared.record(
                .auth, "inviteLinkClaimFailed",
                params: ["vendor": vendorID.uuidString, "error": String(describing: error)],
                severity: .error
            )
            return []
        }
    }

    // MARK: - Sign out

    /// Signs out from Supabase and clears all synced caches.
    ///
    /// Local-only data (events, tracks, blocks, vendors, shift records) is
    /// intentionally preserved — the user still owns it on-device and it
    /// remains fully usable offline after sign-out.
    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut()
        clearSyncedCaches()
        // authStateChanges fires .signedOut → clears session + currentProfile
    }

    // MARK: - Account deletion

    /// Permanently deletes the signed-in user's account and all server-side
    /// data (App Store Guideline 5.1.1(v)).
    ///
    /// The `delete-account` Edge Function removes the caller's voice-memo
    /// objects via the Storage API (hosted Supabase forbids SQL deletes on
    /// storage tables), then deletes the auth user; Postgres cascades take
    /// the profile, owned events, timeline rows, acknowledgments, and device
    /// tokens with it. Vendor links on other planners' events are unlinked,
    /// never deleted.
    ///
    /// Local-only data is preserved, mirroring ``signOut()`` — the on-device
    /// copy still belongs to the user and remains usable offline.
    func deleteAccount() async throws {
        guard let client else { return }
        try await client.functions.invoke("delete-account")
        // The server account is gone, so the remote sign-out call may fail;
        // it still clears the Keychain session and fires .signedOut locally.
        try? await client.auth.signOut()
        clearSyncedCaches()
    }

    // MARK: - Cache clearing

    /// Deletes all Supabase-synced local caches without touching the user's
    /// local-only timeline data (EventModel, TimelineTrack, TimeBlockModel,
    /// VendorModel, ShiftRecord).
    ///
    /// Currently clears: OutboxEntry (pending sync queue).
    /// Future epics will add: Realtime cursors, delta-fetch timestamps, etc.
    func clearSyncedCaches() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: OutboxEntry.self)
        } catch {
            // Non-fatal — sign-out proceeds regardless of cache-clear failure
        }
    }

    // MARK: - Account-switch purge

    /// UserDefaults key holding the last account that established a session
    /// on this device.
    private static let lastAccountKey = "auth.lastEstablishedAccountID"

    /// Purges the previous account's events when a different account signs in.
    ///
    /// Local visibility is deliberately unscoped — the roster, widgets, and
    /// watch read the whole store — so rows synced by a previous account would
    /// otherwise leak to the new one. Runs before the backfill and hydration so
    /// the incoming account starts from a correctly-scoped store.
    private func purgeOtherAccountDataIfSwitched(to userID: UUID) {
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: Self.lastAccountKey).flatMap(UUID.init)
        defaults.set(userID.uuidString, forKey: Self.lastAccountKey)
        guard last != userID else { return }
        purgeEvents(notOwnedBy: userID)
    }

    /// Deletes every event owned by an account other than `userID` —
    /// cascading tracks, blocks, vendors, and shift records — and clears the
    /// Outbox so no pending writes reference the deleted rows.
    ///
    /// What survives, and why:
    /// - `ownerId == nil` events are device-local data that never synced; the
    ///   backfill claims them for the incoming account, mirroring first sign-in.
    /// - Nothing is lost server-side: the previous owner's copy re-hydrates on
    ///   their next sign-in (itself a switch, purging in the other direction).
    ///
    /// Events shared *to* the incoming account are deleted here (their owner is
    /// the sharing planner) and re-pulled by the hydration that immediately
    /// follows — server truth, not the device, decides what the account can see.
    ///
    /// Deletes row-by-row rather than via batch delete so SwiftData honors the
    /// cascade rules.
    func purgeEvents(notOwnedBy userID: UUID) {
        guard let context = modelContext else { return }
        do {
            let stale = try context.fetch(
                FetchDescriptor<EventModel>(
                    predicate: #Predicate { event in
                        event.ownerId != nil && event.ownerId != userID
                    }
                )
            )
            guard !stale.isEmpty else { return }
            for event in stale {
                context.delete(event)
            }
            try context.save()
            clearSyncedCaches()
        } catch {
            // Non-fatal — a failed purge leaves the pre-switch rows in place,
            // exactly as before this guard existed; hydration still proceeds.
        }
    }

    // MARK: - Private

    private func beginListening(using client: SupabaseClient) {
        listenerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                self.session = session
                if event == .initialSession {
                    self.hasResolvedInitialSession = true
                }
                switch event {
                case .signedIn:
                    if let user = session?.user {
                        await self.establishSession(for: user)
                    }
                case .initialSession, .tokenRefreshed:
                    // With `emitLocalSessionAsInitialSession`, the stored session is
                    // emitted on launch even if expired; `.tokenRefreshed` arrives
                    // after the silent refresh. Establish only for a valid session
                    // not yet established this launch — so an expired-at-launch
                    // session waits for its refresh instead of firing failing writes.
                    if let user = session?.user,
                       session?.isExpired == false,
                       self.currentProfile == nil {
                        await self.establishSession(for: user)
                    }
                case .signedOut:
                    self.currentProfile = nil
                    await self.deviceTokenRegistrar?.updateProfile(nil)
                default:
                    break
                }
            }
        }
    }

    /// Post-sign-in side effects, idempotent so they can re-run on a restored or
    /// refreshed session: upsert the profile, claim pending invites,
    /// register this device's APNs token, run the one-time data
    /// backfill (enqueues local rows, gated once per account), then
    /// hydrate the cache from Supabase and drain the Outbox.
    ///
    /// Order matters: backfill *enqueues* local rows before the sync stack
    /// hydrates (pull) and flushes (push) — so a freshly-migrated user's graph is
    /// queued, then uploaded by the same establishment.
    private func establishSession(for user: User) async {
        SyncDiagnosticsCenter.shared.record(
            .auth, "sessionEstablished", params: ["profile": user.id.uuidString]
        )
        purgeOtherAccountDataIfSwitched(to: user.id)
        await performProfileUpsert(user: user, displayName: nil)
        await claimPendingInvites()
        await deviceTokenRegistrar?.updateProfile(user.id)
        await dataBackfiller?.runIfNeeded(profileID: user.id)
        await sessionSync?.onSessionEstablished()
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
            // Use the returned row so the stored display name (set on first
            // sign-in) is shown on every launch, not just the first.
            currentProfile = try await repo.upsert(dto)
        } catch {
            // Non-fatal — SyncDiagnosticsCenter surfaces this.
        }
    }
}
