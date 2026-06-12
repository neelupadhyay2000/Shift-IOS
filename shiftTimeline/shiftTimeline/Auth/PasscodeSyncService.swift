import Foundation
import Supabase

/// Read/write side of the `app_passcodes` table — the per-account mirror of
/// the device passcode record, so a sign-out → OTP sign-in restores the
/// user's existing passcode instead of forcing a new one.
///
/// The record is opaque to the server (salt ‖ PBKDF2 digest, base64 — see
/// `PasscodeStore`); RLS scopes every operation to the caller's own row.
struct PasscodeSyncService: Sendable {

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    private struct RecordRow: Codable {
        let record: String
    }

    private struct UpsertRow: Codable {
        let profileId: UUID
        let record: String

        enum CodingKeys: String, CodingKey {
            case profileId = "profile_id"
            case record
        }
    }

    /// The caller's stored record, or `nil` when none exists (first sign-up).
    func fetchRecord() async throws -> Data? {
        let rows: [RecordRow] = try await client
            .from("app_passcodes")
            .select("record")
            .execute()
            .value
        guard let encoded = rows.first?.record else { return nil }
        return Data(base64Encoded: encoded)
    }

    func upload(record: Data, profileID: UUID) async throws {
        try await client
            .from("app_passcodes")
            .upsert(
                UpsertRow(profileId: profileID, record: record.base64EncodedString()),
                onConflict: "profile_id"
            )
            .execute()
    }

    /// Forgot-passcode path: removes the account record BEFORE signing out,
    /// so the post-OTP restore doesn't reinstall the forgotten passcode.
    func deleteRecord(profileID: UUID) async throws {
        try await client
            .from("app_passcodes")
            .delete()
            .eq("profile_id", value: profileID.uuidString)
            .execute()
    }
}
