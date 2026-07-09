import Foundation
import Models

// MARK: - Sort

/// Ordering for the community browse RPC. Raw values are the `p_sort` wire keys
/// understood by `search_community_templates`.
enum CommunityTemplateSort: String, CaseIterable, Identifiable, Sendable {
    case popular
    case newest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .popular: String(localized: "Popular")
        case .newest:  String(localized: "Newest")
        }
    }
}

// MARK: - Read DTO

/// One row from the `search_community_templates` RPC: a published template plus its
/// author's resolved display name (joined past RLS server-side). Read-only — writes
/// go through `publish_community_template` and the author's own UPDATE policy.
///
/// `blocks` decodes the jsonb array straight into `[TemplateBlock]` (the same shape
/// the publish path encoded), so a community template bridges to the shared
/// `Template` and reuses the existing preview + apply flow unchanged.
nonisolated struct CommunityTemplateDTO: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let authorID: UUID
    let authorName: String
    let name: String
    let description: String
    let category: String
    let blocks: [TemplateBlock]
    let blockCount: Int
    let sourceEventCompleted: Bool
    let timesApplied: Int
    let createdAt: PostgresTimestamp

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case authorName = "author_name"
        case name
        case description
        case category
        case blocks
        case blockCount = "block_count"
        case sourceEventCompleted = "source_event_completed"
        case timesApplied = "times_applied"
        case createdAt = "created_at"
    }
}

// MARK: - Template bridge

extension CommunityTemplateDTO {
    /// The category as the typed enum. Falls back to `.social` if the server ever
    /// returns an unknown value (the table's CHECK prevents this in practice).
    var templateCategory: TemplateCategory {
        TemplateCategory(rawValue: category) ?? .social
    }

    /// Bridges to the shared `Template` so the existing `TemplatePreviewView` and
    /// the event-creation flow render / instantiate a community template unchanged.
    /// The DTO `id` carries through so the apply path can report it back to
    /// `apply_community_template` for the popularity counter.
    var asTemplate: Template {
        Template(
            id: id,
            name: name,
            description: description,
            category: templateCategory,
            blocks: blocks
        )
    }
}

// MARK: - Raw row DTO

/// A raw `community_templates` row — what `publish_community_template` returns and
/// what the author's "Published by you" list reads (direct select past the author
/// RLS policy). Carries `isPublished` / `deletedAt` so the management UI can show
/// status; no `author_name` (it's always the caller).
nonisolated struct CommunityTemplateRowDTO: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let authorID: UUID
    let name: String
    let description: String
    let category: String
    let blocks: [TemplateBlock]
    let blockCount: Int
    let sourceEventCompleted: Bool
    let timesApplied: Int
    let isPublished: Bool
    let createdAt: PostgresTimestamp
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case name
        case description
        case category
        case blocks
        case blockCount = "block_count"
        case sourceEventCompleted = "source_event_completed"
        case timesApplied = "times_applied"
        case isPublished = "is_published"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
}

extension CommunityTemplateRowDTO {
    /// The category as the typed enum (see `CommunityTemplateDTO.templateCategory`).
    var templateCategory: TemplateCategory {
        TemplateCategory(rawValue: category) ?? .social
    }

    /// Bridges to the shared `Template` for preview / re-use.
    var asTemplate: Template {
        Template(
            id: id,
            name: name,
            description: description,
            category: templateCategory,
            blocks: blocks
        )
    }
}
