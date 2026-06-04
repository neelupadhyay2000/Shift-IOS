import Foundation

/// Row in the Supabase `tracks` table. Mirrors `TimelineTrack`.
///
/// The `event` relationship is carried by `event_id` (a foreign key) rather
/// than a nested object — relationships are wired by id in the mapping layer.
nonisolated struct TrackDTO: Codable, Equatable {
    let id: UUID
    let eventID: UUID
    let name: String
    let sortOrder: Int
    let isDefault: Bool
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case name
        case sortOrder = "sort_order"
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        eventID: UUID,
        name: String,
        sortOrder: Int,
        isDefault: Bool,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.name = name
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
