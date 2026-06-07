import Foundation
import Supabase

// MARK: - DTO

/// Payload for upserting a row in the Supabase `profiles` table.
///
/// Only non-nil fields are included in the encoded JSON — nil fields are
/// omitted entirely so an upsert on a returning user never overwrites
/// existing Postgres values with NULL.
///
/// All conformance witnesses are explicitly `nonisolated` so Swift 6's
/// conformance-isolation inference does not mark them as `@MainActor`-isolated
/// when `ProfileDTO` is stored in `SupabaseAuthService` (`@Observable @MainActor`).
// swiftformat:disable:next redundantSendable
struct ProfileDTO: Sendable {
    let id: UUID
    let displayName: String?
    let phone: String?
    let email: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phone
        case email
    }
}

// MARK: - Encodable

extension ProfileDTO: Encodable {
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let displayName { try container.encode(displayName, forKey: .displayName) }
        if let phone { try container.encode(phone, forKey: .phone) }
        if let email { try container.encode(email, forKey: .email) }
    }
}

// MARK: - Decodable

extension ProfileDTO: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }
}

// MARK: - Equatable

// swiftformat:disable all
extension ProfileDTO: Equatable {
    nonisolated static func == (lhs: ProfileDTO, rhs: ProfileDTO) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.phone == rhs.phone
            && lhs.email == rhs.email
    }
}
// swiftformat:enable all

// MARK: - Protocol

/// Write-side protocol for the Supabase `profiles` table.
///
/// The upsert is conflict-resolved on `id` (= `auth.uid()`), so calling
/// it on a returning user updates only the fields present in the payload
/// rather than inserting a duplicate row.
protocol ProfileRepositing: Sendable {
    /// Upserts and returns the resulting stored row. Because the encode omits nil
    /// fields, a returning user's upsert keeps the server's existing values (e.g.
    /// the display name captured on first Apple sign-in) — and the returned row
    /// carries them back, so the UI can show the name on every launch.
    @discardableResult
    func upsert(_ profile: ProfileDTO) async throws -> ProfileDTO
}

// MARK: - Supabase Implementation

/// Supabase-backed `ProfileRepositing`. Stateless — holds only the shared client.
struct SupabaseProfileRepository: ProfileRepositing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    @discardableResult
    func upsert(_ profile: ProfileDTO) async throws -> ProfileDTO {
        try await client
            .from("profiles")
            .upsert(profile, onConflict: "id")
            .select()
            .single()
            .execute()
            .value
    }
}
