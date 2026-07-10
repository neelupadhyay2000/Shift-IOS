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
        didSet {
            SubscriptionManager.shared.compedUntil = currentProfile?.compedUntil?.value
            // Cache the name for the "Welcome back, <name>" landing a signed-out
            // returning user sees. Only overwrite with a real name — never clear
            // it on a transient nil profile (offline), so the greeting survives.
            if let name = currentProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                AuthMethodStore.lastDisplayName = name
            }
        }
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

    /// E19 gate: a signed-in user whose profile row exists but is not yet onboarded
    /// must complete profile creation before reaching the app. Only forces the flow
    /// when the profile has loaded AND explicitly reports `onboarded == false` — a
    /// nil profile (still loading / offline) never blocks a returning user.
    var needsOnboarding: Bool {
        isAuthenticated && currentProfile?.onboarded == false
    }

    /// E21 exclusive persona. The app hard-gates marketplace features on this:
    /// a vendor account gets a listing + received requests and can't request
    /// vendors; a planner account requests vendors and has no vendor tools.
    /// Defaults to planner when the type is unknown (loading / legacy).
    var isVendorAccount: Bool {
        currentProfile?.accountType == "vendor"
    }

    /// Completion gate (2026-06-25): an already-onboarded account that is still
    /// missing a required field — a name (all accounts) or a valid email (all
    /// accounts; phone-signups must add one). Catches legacy accounts created
    /// before the rule; new accounts satisfy it during onboarding. Only fires
    /// once the profile has loaded and reports `onboarded == true`, so it never
    /// blocks a still-loading or mid-onboarding user.
    var needsProfileCompletion: Bool {
        guard isAuthenticated, currentProfile?.onboarded == true else { return false }
        return !ProfileCompleteness.isComplete(
            name: currentProfile?.displayName,
            email: accountEmail,
            phone: accountPhone
        )
    }

    /// The account's email — the auth identity's address if present, otherwise
    /// the `profiles` mirror. Exposed so views don't need to import the Supabase
    /// `User` type just to read it.
    ///
    /// GoTrue serializes a phone-only user's `email` as an empty string `""`
    /// (not nil), so a plain `??` would never fall back to the profiles value —
    /// treat blank as absent so a phone-signup's saved email is what counts.
    var accountEmail: String? {
        if let sessionEmail = session?.user.email,
           !sessionEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sessionEmail
        }
        return currentProfile?.email
    }

    /// The account's phone — the verified auth identity if present, else the
    /// `profiles` mirror (where an email-signup's added phone is stored, unverified
    /// in the soft model). Same blank-as-absent handling as ``accountEmail``.
    var accountPhone: String? {
        if let sessionPhone = session?.user.phone,
           !sessionPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sessionPhone
        }
        return currentProfile?.phone
    }

    /// Re-reads the signed-in profile row (e.g. after onboarding completes) so
    /// `needsOnboarding` re-evaluates and the gate dismisses.
    func refreshProfile() async {
        guard let repo = profileRepository, let uid = currentProfileID else { return }
        if let fresh = try? await repo.fetch(profileID: uid) {
            currentProfile = fresh
        }
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

    // MARK: - Identifier uniqueness

    /// Asks the backend whether an email and/or phone already belongs to an
    /// account — checking both verified identities (`auth.users`) and stored second
    /// credentials (`profiles`), in both directions. This is the one-person-one-
    /// account gate: a signup whose identifier is already in use is refused, and
    /// the Edit screen uses `*_is_mine` to avoid flagging a user's own credential.
    ///
    /// Fail-open on a network error: a false "it's free" is caught by the DB's
    /// unique-index backstop at write time, whereas a false "it's taken" would
    /// block a legitimate signup. So the caller treats a throw as "couldn't check"
    /// and proceeds, rather than as a collision.
    func identifierStatus(email: String?, phone: String?) async throws -> IdentifierStatus {
        guard let client else { throw AccountIdentityError.notSignedIn }
        let rows: [IdentifierStatus] = try await client
            .rpc("identifier_status", params: IdentifierStatusParams(email: email, phone: phone))
            .execute()
            .value
        return rows.first ?? .free
    }

    // MARK: - Account identity editing

    /// Renames the account. `display_name` lives only on `profiles`, so this is a
    /// plain write — no re-verification, unlike an email or phone change.
    func updateDisplayName(_ name: String) async throws {
        guard let client, let uid = currentProfileID else {
            throw AccountIdentityError.notSignedIn
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountIdentityError.blankName }

        try await client.from("profiles")
            .update(["display_name": trimmed])
            .eq("id", value: uid.uuidString)
            .execute()
        await refreshProfile()
    }

    /// Starts an email change. GoTrue mails a 6-digit code to the **new** address
    /// and — because `double_confirm_changes` is on — a second, different code to
    /// the **current** one. Both must be verified before the change commits, which
    /// is what stops someone holding a live session on an unlocked phone from
    /// silently moving the account to their own address.
    ///
    /// Returns the addresses that were sent a code, in the order the UI should ask
    /// for them: the new address first (the user is looking at that inbox), then
    /// the old. An account with no email yet has only the one.
    @discardableResult
    func beginEmailChange(to newEmail: String) async throws -> [String] {
        guard let client else { throw AccountIdentityError.notSignedIn }
        let normalized = EmailAuthService.normalizeEmail(newEmail)
        guard EmailAuthService.isValidEmail(normalized) else {
            throw AccountIdentityError.invalidEmail
        }
        let current = AccountIdentity.nonEmpty(currentUser?.email)
        guard current?.lowercased() != normalized else {
            throw AccountIdentityError.unchanged
        }

        // Refuse an address already on another account, with a clean message.
        // GoTrue enforces this too, but its error is opaque. Fail-open on a check
        // error — GoTrue is still the hard gate.
        if let status = try? await identifierStatus(email: normalized, phone: nil),
           status.emailTakenByOther {
            throw AccountIdentityError.emailInUse
        }

        try await client.auth.update(user: UserAttributes(email: normalized))

        // New address first: that's the inbox the user is already looking at. The
        // old address only appears when double confirmation is on and there is one.
        var legs = [normalized]
        if let current { legs.append(current) }
        return legs
    }

    /// Verifies one leg of an email change. Returns `true` once the change has
    /// fully committed — i.e. `auth.users.email` is the new address and no pending
    /// change remains. With double confirmation the first call returns `false`;
    /// the caller then collects the code sent to the other address.
    ///
    /// The completion test reads the *server's* user, never a local guess: GoTrue
    /// is the only thing that knows whether both legs landed.
    func confirmEmailChange(address: String, token: String) async throws -> Bool {
        guard let client else { throw AccountIdentityError.notSignedIn }
        _ = try await client.auth.verifyOTP(
            email: EmailAuthService.normalizeEmail(address),
            token: token,
            type: .emailChange
        )
        let user = try await client.auth.user()
        let committed = user.newEmail == nil
        if committed { try await mirrorIdentityToProfile(user) }
        return committed
    }

    /// Starts a phone change (or adds a phone to an email-only account). GoTrue
    /// texts a 6-digit code to the new number via Twilio Verify. There is no
    /// double-confirm equivalent for SMS, so this is a single leg.
    func beginPhoneChange(to newPhone: String) async throws {
        guard let client else { throw AccountIdentityError.notSignedIn }
        let normalized = PhoneAuthService.normalizePhone(newPhone)
        guard PhoneAuthService.isValidE164(normalized) else {
            throw AccountIdentityError.invalidPhone
        }
        // GoTrue stores `auth.users.phone` without the leading '+', so compare on
        // digits rather than on the formatted string.
        let currentDigits = (currentUser?.phone ?? "").filter(\.isNumber)
        guard currentDigits != normalized.filter(\.isNumber) else {
            throw AccountIdentityError.unchanged
        }

        if let status = try? await identifierStatus(email: nil, phone: normalized),
           status.phoneTakenByOther {
            throw AccountIdentityError.phoneInUse
        }

        try await client.auth.update(user: UserAttributes(phone: normalized))
    }

    /// Verifies the code texted to the new number and commits the change.
    func confirmPhoneChange(phone: String, token: String) async throws {
        guard let client else { throw AccountIdentityError.notSignedIn }
        _ = try await client.auth.verifyOTP(
            phone: PhoneAuthService.normalizePhone(phone),
            token: token,
            type: .phoneChange
        )
        let user = try await client.auth.user()
        try await mirrorIdentityToProfile(user)
    }

    /// Copies the committed credential down into `profiles`, the app's source of
    /// truth for identity display. Without this the Account screen would keep
    /// showing the old address until the next cold launch, and every server-side
    /// lookup keyed on `profiles.email` (comp grants, moderation contact) would
    /// still point at an address the user no longer controls.
    private func mirrorIdentityToProfile(_ user: User) async throws {
        guard let client, let uid = currentProfileID else { return }
        var fields: [String: String] = [:]
        if let email = AccountIdentity.nonEmpty(user.email) { fields["email"] = email }
        if let phone = AccountIdentity.nonEmpty(user.phone) { fields["phone"] = phone }
        guard !fields.isEmpty else { return }

        try await client.from("profiles")
            .update(fields)
            .eq("id", value: uid.uuidString)
            .execute()
        await refreshProfile()
    }

    // MARK: - Profile completion

    /// Fills in the account's missing required fields (the completion gate's
    /// write): name, email, and — since 2026-07-10 — phone. `profiles` is the
    /// single source of truth; in the soft uniqueness model the second credential
    /// is stored here unverified, not attached to the GoTrue identity.
    ///
    /// Rejects a credential already used by another account. The DB's unique
    /// indexes are the hard backstop (a racing write fails 23505), but checking
    /// first lets us return a clean, specific message instead of a raw constraint
    /// error. Skips the check for a credential the account already owns.
    func completeProfile(name: String?, email: String?, phone: String?) async throws {
        guard let client, let uid = currentProfileID else {
            throw ProfileCompletionError.notSignedIn
        }
        let trimmedNameRaw = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedName = trimmedNameRaw.isEmpty ? nil : trimmedNameRaw
        let normalizedEmail = email.map(EmailAuthService.normalizeEmail) ?? ""
        let trimmedEmail = normalizedEmail.isEmpty ? nil : normalizedEmail
        let normalizedPhone = phone.map(PhoneAuthService.normalizePhone) ?? ""
        let trimmedPhone = PhoneAuthService.isValidE164(normalizedPhone) ? normalizedPhone : nil

        // One-account-per-identifier: refuse a credential that belongs to someone
        // else before writing it. Fail-open on a check error — the unique index
        // still guards the write.
        if trimmedEmail != nil || trimmedPhone != nil {
            let status = try? await identifierStatus(email: trimmedEmail, phone: trimmedPhone)
            if let status {
                if status.emailTakenByOther { throw ProfileCompletionError.emailInUse }
                if status.phoneTakenByOther { throw ProfileCompletionError.phoneInUse }
            }
        }

        var fields: [String: String] = [:]
        if let trimmedName { fields["display_name"] = trimmedName }
        if let trimmedEmail { fields["email"] = trimmedEmail }
        if let trimmedPhone { fields["phone"] = trimmedPhone }
        guard !fields.isEmpty else { return }

        do {
            try await client.from("profiles").update(fields).eq("id", value: uid.uuidString).execute()
        } catch {
            // The unique-index backstop fired: a concurrent write claimed it first.
            throw Self.mapIdentifierConflict(error) ?? error
        }
        await refreshProfile()
    }

    /// Maps a Postgres 23505 on the identifier indexes to a friendly error, so a
    /// lost race surfaces the same message as the pre-check. Returns nil for any
    /// other error (the caller rethrows it unchanged).
    private static func mapIdentifierConflict(_ error: Error) -> ProfileCompletionError? {
        let text = String(describing: error).lowercased()
        guard text.contains("23505") || text.contains("duplicate key") else { return nil }
        if text.contains("phone") { return .phoneInUse }
        if text.contains("email") { return .emailInUse }
        return nil
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
        // The account no longer exists — forget the remembered method/name so
        // the next person on this device sees a clean welcome, not "Welcome
        // back, <deleted user>".
        AuthMethodStore.clear()
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
                        // Synchronously, before the first await: the gate must
                        // see "restore pending" in the same render pass that
                        // sees the session, or the setup UI flashes.
                        AppLock.shared.beginAccountRestore()
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
                        AppLock.shared.beginAccountRestore()
                        await self.establishSession(for: user)
                    }
                case .signedOut:
                    self.currentProfile = nil
                    // The device passcode belongs to the signed-in identity:
                    // wipe it so the next sign-in re-creates one (also the
                    // forgot-passcode path, which signs out to re-prove via OTP).
                    AppLock.shared.resetForSignOut()
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
        // Remember how this account proves identity so recovery flows
        // (forgot-passcode) can route back to the right OTP screen. A phone
        // sign-in carries a non-empty `phone`; everything else is email.
        AuthMethodStore.last = (user.phone?.isEmpty == false) ? .phone : .email
        purgeOtherAccountDataIfSwitched(to: user.id)
        await performProfileUpsert(user: user, displayName: nil)
        await restorePasscode(for: user)
        await claimPendingInvites()
        await deviceTokenRegistrar?.updateProfile(user.id)
        await dataBackfiller?.runIfNeeded(profileID: user.id)
        await sessionSync?.onSessionEstablished()
    }

    /// Syncs the account-level passcode record (see `PasscodeSyncService`).
    ///
    /// Remote wins: installing the server record after every sign-in both
    /// restores the passcode after a sign-out (no re-creation) and propagates
    /// a change made on another device. A local record uploads only when the
    /// server has none — e.g. it was created offline — healing on the next
    /// establishment. Best-effort: failure just means the setup screen shows.
    private func restorePasscode(for user: User) async {
        defer { AppLock.shared.finishAccountRestore() }
        guard let client else { return }
        let sync = PasscodeSyncService(client: client)
        do {
            if let remote = try await sync.fetchRecord() {
                AppLock.shared.installRestoredRecord(remote)
            } else if let local = AppLock.shared.currentRecord() {
                try await sync.upload(record: local, profileID: user.id)
            }
        } catch {
            // Offline or transient — non-fatal by design.
        }
    }

    /// Mirrors the auth identity into `profiles` on every session establishment.
    ///
    /// Blanks are stripped, and that is load-bearing. GoTrue serializes a
    /// phone-only user's `email` as `""` rather than nil (see ``accountEmail``),
    /// and `ProfileDTO.encode` writes any non-nil value — including `""`. So this
    /// used to overwrite `profiles.email` with an empty string on every launch,
    /// destroying the address a phone signup had just supplied in
    /// `CompleteProfileView` and flipping `needsProfileCompletion` back to true.
    /// The account was re-gated forever, one launch at a time. The same applies to
    /// `phone` on an email-only account, which `comp_account` now matches on.
    ///
    /// A blank here always means "this identity has no such field", never "clear
    /// the stored one" — the only path that clears a credential is a verified
    /// change (see ``mirrorIdentityToProfile(_:)``).
    private func performProfileUpsert(user: User, displayName: String?) async {
        guard let repo = profileRepository else { return }
        let dto = ProfileDTO(
            id: user.id,
            displayName: displayName,
            phone: AccountIdentity.nonEmpty(user.phone),
            email: AccountIdentity.nonEmpty(user.email)
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
