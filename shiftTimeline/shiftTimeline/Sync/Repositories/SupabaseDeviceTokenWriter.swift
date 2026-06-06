import Foundation
import Supabase

/// Registers this device's APNs token in Supabase (SHIFT-642).
///
/// `device_tokens` has RLS enabled with **no table policies** — it carries APNs
/// routing data, is excluded from the realtime publication, and must never be
/// read or written directly by a client. Registration therefore goes through the
/// `upsert_device_token` SECURITY DEFINER RPC, which derives `profile_id` from
/// the caller's verified `auth.uid()` (so a client can't register a token under
/// another profile) and upserts on the unique `apns_token`, re-keying the owner
/// on an account switch. Mirrors the `claim_invite` RPC precedent (SHIFT-628).
protocol DeviceTokenWriting: Sendable {
    /// Upserts the caller's APNs token + environment. `profile_id` is resolved
    /// server-side from `auth.uid()`, never sent by the client.
    func upsert(apnsToken: String, environment: String) async throws
}

/// Supabase-backed `DeviceTokenWriting`. Stateless — holds only the shared client.
struct SupabaseDeviceTokenWriter: DeviceTokenWriting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upsert(apnsToken: String, environment: String) async throws {
        try await client
            .rpc("upsert_device_token", params: [
                "p_apns_token": apnsToken,
                "p_environment": environment,
            ])
            .execute()
    }
}
