import Foundation
import Supabase

// MARK: - DTO

/// Payload for upserting a row in the Supabase `profiles` table.
///
/// Only non-nil fields are included in the encoded JSON — nil fields are
/// omitted entirely so an upsert on a returning user never overwrites
/// existing Postgres values with NULL.
struct ProfileDTO: Codable, Equatable {
    let id: UUID
    let displayName: String?
    let phone: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phone
        case email
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let displayName { try container.encode(displayName, forKey: .displayName) }
        if let phone { try container.encode(phone, forKey: .phone) }
        if let email { try container.encode(email, forKey: .email) }
    }
}

// MARK: - Protocol

/// Write-side protocol for the Supabase `profiles` table.
///
/// The upsert is conflict-resolved on `id` (= `auth.uid()`), so calling
/// it on a returning user updates only the fields present in the payload
/// rather than inserting a duplicate row.
protocol ProfileRepositing: Sendable {
    func upsert(_ profile: ProfileDTO) async throws
}

// MARK: - Supabase Implementation

/// Supabase-backed `ProfileRepositing`. Stateless — holds only the shared client.
struct SupabaseProfileRepository: ProfileRepositing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upsert(_ profile: ProfileDTO) async throws {
        try await client
            .from("profiles")
            .upsert(profile, onConflict: "id")
            .execute()
    }
}
