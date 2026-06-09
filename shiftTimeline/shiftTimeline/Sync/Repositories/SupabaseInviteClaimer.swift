import Foundation
import Supabase

/// Runs the authoritative server-side invite claim (SHIFT-628).
///
/// The match runs entirely in the `claim_invite` Postgres function against the
/// caller's **verified** `auth.users` identity, so a client cannot claim an
/// invite that wasn't addressed to it (and cannot help itself by rewriting its
/// own `profiles` row). The client's only job is to call it on sign-in.
protocol InviteClaiming: Sendable {
    /// Calls `claim_invite()` and returns the `event_vendors` rows the server
    /// linked to the signed-in identity (empty when there's nothing to claim).
    func claimInvites() async throws -> [EventVendorDTO]

    /// Calls `claim_invite_by_id(vendorID)` — the possession-based claim for a
    /// tapped invite link. Claims that one row for the signed-in user regardless
    /// of identity match, so a phone-addressed invite works via any sign-in
    /// method (e.g. email OTP) without phone OTP.
    func claimInvite(vendorID: UUID) async throws -> [EventVendorDTO]
}

/// Supabase-backed `InviteClaiming`. Stateless — holds only the shared client.
struct SupabaseInviteClaimer: InviteClaiming {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func claimInvites() async throws -> [EventVendorDTO] {
        try await client
            .rpc("claim_invite")
            .execute()
            .value
    }

    func claimInvite(vendorID: UUID) async throws -> [EventVendorDTO] {
        try await client
            .rpc("claim_invite_by_id", params: ["p_vendor_id": vendorID.uuidString])
            .execute()
            .value
    }
}
