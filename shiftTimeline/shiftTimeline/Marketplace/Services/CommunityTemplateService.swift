import Foundation
import Models
import Supabase
import SwiftUI

// MARK: - Params

/// Typed args for `search_community_templates` (wire keys match the SQL).
nonisolated struct SearchCommunityTemplatesParams: Encodable, Sendable {
    let pCategory: String?
    let pQuery: String
    let pSort: String
    let pLimit: Int
    let pOffset: Int

    enum CodingKeys: String, CodingKey {
        case pCategory = "p_category"
        case pQuery = "p_query"
        case pSort = "p_sort"
        case pLimit = "p_limit"
        case pOffset = "p_offset"
    }
}

/// Typed args for `publish_community_template`. `pSourceEventID` is omitted from the
/// JSON when nil (synthesized `encodeIfPresent`), so the RPC sees its SQL default
/// and the template publishes unverified.
nonisolated struct PublishCommunityTemplateParams: Encodable, Sendable {
    let pName: String
    let pDescription: String
    let pCategory: String
    let pBlocks: [TemplateBlock]
    let pBlockCount: Int
    let pSourceEventID: UUID?

    enum CodingKeys: String, CodingKey {
        case pName = "p_name"
        case pDescription = "p_description"
        case pCategory = "p_category"
        case pBlocks = "p_blocks"
        case pBlockCount = "p_block_count"
        case pSourceEventID = "p_source_event_id"
    }
}

/// Typed arg for `apply_community_template`.
nonisolated struct ApplyCommunityTemplateParams: Encodable, Sendable {
    let pTemplateID: UUID

    enum CodingKeys: String, CodingKey {
        case pTemplateID = "p_template_id"
    }
}

// MARK: - Protocol

/// Community templates (E23). Online-only direct Supabase access, like the other
/// marketplace services. Publishing goes through the gated `publish_community_template`
/// RPC (the only insert path); browse reads `search_community_templates`; applying
/// bumps the popularity counter via `apply_community_template`; the author manages
/// their own rows through the author RLS policy.
protocol CommunityTemplateProviding: Sendable {
    /// Published templates for the directory, filtered + ordered server-side.
    func browse(
        category: TemplateCategory?,
        query: String,
        sort: CommunityTemplateSort,
        limit: Int,
        offset: Int
    ) async throws -> [CommunityTemplateDTO]

    /// Publishes a template. Pass `sourceEventID` for the "Verified — run in Shift"
    /// badge; the server only honours it when the event is completed and caller-owned.
    @discardableResult
    func publish(_ template: Template, sourceEventID: UUID?) async throws -> CommunityTemplateRowDTO

    /// Best-effort popularity bump after a community template is applied.
    func recordApply(templateID: UUID) async throws

    /// The caller's own published templates (incl. unpublished), newest first.
    func myTemplates() async throws -> [CommunityTemplateRowDTO]

    /// Toggles a template's visibility (author only).
    func setPublished(templateID: UUID, isPublished: Bool) async throws

    /// Soft-deletes a template the caller authored (author only).
    func softDelete(templateID: UUID) async throws
}

// MARK: - Supabase implementation

@MainActor
struct SupabaseCommunityTemplateService: CommunityTemplateProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func browse(
        category: TemplateCategory? = nil,
        query: String = "",
        sort: CommunityTemplateSort = .popular,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [CommunityTemplateDTO] {
        let params = SearchCommunityTemplatesParams(
            pCategory: category?.rawValue,
            pQuery: query.trimmingCharacters(in: .whitespacesAndNewlines),
            pSort: sort.rawValue,
            pLimit: limit,
            pOffset: max(0, offset)
        )
        return try await client
            .rpc("search_community_templates", params: params)
            .execute()
            .value
    }

    @discardableResult
    func publish(_ template: Template, sourceEventID: UUID?) async throws -> CommunityTemplateRowDTO {
        let params = PublishCommunityTemplateParams(
            pName: template.name.trimmingCharacters(in: .whitespacesAndNewlines),
            pDescription: template.description.trimmingCharacters(in: .whitespacesAndNewlines),
            pCategory: template.category.rawValue,
            pBlocks: template.blocks,
            pBlockCount: template.blocks.count,
            pSourceEventID: sourceEventID
        )
        let rows: [CommunityTemplateRowDTO] = try await client
            .rpc("publish_community_template", params: params)
            .execute()
            .value
        guard let row = rows.first else { throw CommunityTemplateError.emptyResponse }
        return row
    }

    func recordApply(templateID: UUID) async throws {
        let params = ApplyCommunityTemplateParams(pTemplateID: templateID)
        try await client
            .rpc("apply_community_template", params: params)
            .execute()
    }

    func myTemplates() async throws -> [CommunityTemplateRowDTO] {
        let uid = try await client.auth.session.user.id
        return try await client
            .from("community_templates")
            .select()
            .eq("author_id", value: uid.uuidString)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func setPublished(templateID: UUID, isPublished: Bool) async throws {
        try await client
            .from("community_templates")
            .update(["is_published": isPublished])
            .eq("id", value: templateID.uuidString)
            .execute()
    }

    func softDelete(templateID: UUID) async throws {
        try await client
            .from("community_templates")
            .update(["deleted_at": SupabaseTimestamp.string(from: Date())])
            .eq("id", value: templateID.uuidString)
            .execute()
    }
}

enum CommunityTemplateError: Error {
    case emptyResponse
}

// MARK: - Environment

/// `nil` until the Supabase-backed service is wired at the scene level (offline /
/// tests / sync disabled). The community UI treats `nil` as "unavailable" and
/// falls back to the coming-soon teaser.
private struct CommunityTemplateServiceKey: EnvironmentKey {
    static let defaultValue: (any CommunityTemplateProviding)? = nil
}

extension EnvironmentValues {
    var communityTemplateService: (any CommunityTemplateProviding)? {
        get { self[CommunityTemplateServiceKey.self] }
        set { self[CommunityTemplateServiceKey.self] = newValue }
    }
}
