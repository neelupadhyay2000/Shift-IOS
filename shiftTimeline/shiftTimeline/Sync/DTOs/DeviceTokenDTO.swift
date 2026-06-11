import Foundation

/// Row in the Supabase `device_tokens` table.
///
/// An APNs token registry keyed per profile, consumed by the Edge Function push
/// path. It has no SwiftData model counterpart — it is populated
/// directly from device registration. `environment` is `sandbox` or `prod` and
/// must match the app's `aps-environment` entitlement.
nonisolated struct DeviceTokenDTO: Codable, Equatable {
    let id: UUID
    let profileID: UUID
    let apnsToken: String
    let environment: String
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case apnsToken = "apns_token"
        case environment
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        profileID: UUID,
        apnsToken: String,
        environment: String,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.apnsToken = apnsToken
        self.environment = environment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
