import Foundation
import Supabase
import SwiftUI

// MARK: - Protocol

/// UGC safety surface (Apple Guideline 1.2): file abuse reports and block/unblock
/// other users. Online-only by design — like ``WaitlistServing``, NOT part of the
/// SwiftData/Outbox sync stack. RLS scopes every write to the caller
/// (`content_reports_insert_own`, `user_blocks_blocker_all`); the server-side
/// `search_vendors` RPC applies blocks bidirectionally, and clients additionally
/// filter blocked users out of reviews / message reads via ``blockedProfileIDs``.
protocol ContentReporting: Sendable {
    /// Files (or idempotently re-files) a report against a piece of content.
    func report(contentType: ReportableContentType, contentID: UUID, reason: ReportReason) async throws

    /// Blocks another user. Idempotent on the `(blocker, blocked)` pair.
    func block(profileID: UUID) async throws

    /// Removes a block the caller previously created.
    func unblock(profileID: UUID) async throws

    /// The set of profile IDs the caller has blocked — for client-side exclusion
    /// in surfaces that don't go through the bidirectional search RPC (reviews,
    /// message reads).
    func blockedProfileIDs() async throws -> Set<UUID>
}

// MARK: - Supabase implementation

/// Supabase-backed ``ContentReporting``. Stateless — holds only the shared client;
/// RLS scopes every query to the caller's own rows.
struct SupabaseContentReportService: ContentReporting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func report(contentType: ReportableContentType, contentID: UUID, reason: ReportReason) async throws {
        let reporterID = try await client.auth.session.user.id
        let payload = Self.reportPayload(
            reporterID: reporterID,
            contentType: contentType,
            contentID: contentID,
            reason: reason
        )
        try await client
            .from("content_reports")
            .upsert(payload, onConflict: "reporter_id,content_type,content_id")
            .execute()
    }

    func block(profileID: UUID) async throws {
        let blockerID = try await client.auth.session.user.id
        let payload = UserBlockDTO(blockerID: blockerID, blockedID: profileID)
        try await client
            .from("user_blocks")
            .upsert(payload, onConflict: "blocker_id,blocked_id")
            .execute()
    }

    func unblock(profileID: UUID) async throws {
        let blockerID = try await client.auth.session.user.id
        try await client
            .from("user_blocks")
            .delete()
            .eq("blocker_id", value: blockerID.uuidString)
            .eq("blocked_id", value: profileID.uuidString)
            .execute()
    }

    func blockedProfileIDs() async throws -> Set<UUID> {
        let blockerID = try await client.auth.session.user.id
        let rows: [UserBlockDTO] = try await client
            .from("user_blocks")
            .select("blocker_id,blocked_id")
            .eq("blocker_id", value: blockerID.uuidString)
            .execute()
            .value
        return Set(rows.map(\.blockedID))
    }

    /// Pure payload construction, exposed internally for tests: the report reason
    /// rides the free-text `reason` column as its raw value.
    static func reportPayload(
        reporterID: UUID,
        contentType: ReportableContentType,
        contentID: UUID,
        reason: ReportReason
    ) -> ContentReportDTO {
        ContentReportDTO(
            reporterID: reporterID,
            contentType: contentType.rawValue,
            contentID: contentID,
            reason: reason.rawValue
        )
    }
}

// MARK: - Environment

/// `nil` until the Supabase-backed service is wired at the scene level; the safety
/// menu treats `nil` as "reporting unavailable" and disables itself.
private struct ContentReportServiceKey: EnvironmentKey {
    static let defaultValue: (any ContentReporting)? = nil
}

extension EnvironmentValues {
    var contentReportService: (any ContentReporting)? {
        get { self[ContentReportServiceKey.self] }
        set { self[ContentReportServiceKey.self] = newValue }
    }
}
