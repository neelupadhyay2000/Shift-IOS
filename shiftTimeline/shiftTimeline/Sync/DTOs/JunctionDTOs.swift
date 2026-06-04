import Foundation

/// Row in the Supabase `block_vendors` junction table (M:N blocks ↔ vendors).
///
/// Mirrors the `TimeBlockModel.vendors` / `VendorModel.assignedBlocks`
/// relationship. The table has a composite primary key `(block_id,
/// event_vendor_id)` and no `id` or `updated_at`; `event_id` is denormalized
/// for RLS and Realtime filtering.
nonisolated struct BlockVendorDTO: Codable, Equatable {
    let blockID: UUID
    let eventVendorID: UUID
    let eventID: UUID
    let createdAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case eventVendorID = "event_vendor_id"
        case eventID = "event_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    init(
        blockID: UUID,
        eventVendorID: UUID,
        eventID: UUID,
        createdAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.blockID = blockID
        self.eventVendorID = eventVendorID
        self.eventID = eventID
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

/// Row in the Supabase `block_dependencies` junction table (self M:N
/// blocks ↔ blocks).
///
/// Mirrors the `TimeBlockModel.dependencies` / `TimeBlockModel.dependents`
/// relationship: `block_id` depends on `depends_on_block_id`. Composite primary
/// key `(block_id, depends_on_block_id)`, no `id` or `updated_at`; `event_id`
/// is denormalized for RLS and Realtime filtering.
nonisolated struct BlockDependencyDTO: Codable, Equatable {
    let blockID: UUID
    let dependsOnBlockID: UUID
    let eventID: UUID
    let createdAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case dependsOnBlockID = "depends_on_block_id"
        case eventID = "event_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    init(
        blockID: UUID,
        dependsOnBlockID: UUID,
        eventID: UUID,
        createdAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.blockID = blockID
        self.dependsOnBlockID = dependsOnBlockID
        self.eventID = eventID
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
