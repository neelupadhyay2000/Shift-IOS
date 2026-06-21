import Foundation
import Supabase
import SwiftUI

// MARK: - Protocol

/// Read/write surface for a service request's chat (E12). Online-only direct
/// Supabase access; realtime streaming lives in ``RequestThreadLive`` (vended by
/// `makeThreadLive`). RLS (`can_access_request`) scopes every query to the
/// request's two participants.
protocol RequestMessaging: Sendable {
    /// A page of messages oldest→newest. `before` is the cursor: pass the oldest
    /// loaded message's `created_at` to page further back; nil loads the latest.
    func messages(requestID: UUID, before: Date?, limit: Int) async throws -> [RequestMessageDTO]

    /// Sends a message. The caller supplies `clientID` so the optimistic copy and
    /// the realtime echo dedupe; returns the stored row.
    @discardableResult
    func send(requestID: UUID, body: String, clientID: UUID) async throws -> RequestMessageDTO

    /// A realtime presence object for the thread (separate from the sync stack).
    @MainActor
    func makeThreadLive(requestID: UUID) -> RequestThreadLive
}

// MARK: - Supabase implementation

struct SupabaseRequestMessagingService: RequestMessaging {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func messages(requestID: UUID, before: Date? = nil, limit: Int = 30) async throws -> [RequestMessageDTO] {
        let base = client
            .from("request_messages")
            .select()
            .eq("request_id", value: requestID.uuidString)
            .is("deleted_at", value: nil)
        // Cursor: strictly-older than the oldest loaded message.
        let filtered = before.map { base.lt("created_at", value: SupabaseTimestamp.string(from: $0)) } ?? base
        let rows: [RequestMessageDTO] = try await filtered
            .order("created_at", ascending: false)
            .limit(max(1, limit))
            .execute()
            .value
        // Fetched newest→oldest for the cursor; return oldest→newest for display/merge.
        return Array(rows.reversed())
    }

    @discardableResult
    func send(requestID: UUID, body: String, clientID: UUID = UUID()) async throws -> RequestMessageDTO {
        let senderID = try await client.auth.session.user.id
        let payload = RequestMessageInsert(
            id: clientID,
            requestID: requestID,
            senderID: senderID,
            body: body
        )
        return try await client
            .from("request_messages")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    @MainActor
    func makeThreadLive(requestID: UUID) -> RequestThreadLive {
        RequestThreadLive(client: client, requestID: requestID)
    }
}

// MARK: - Environment

private struct RequestMessagingServiceKey: EnvironmentKey {
    static let defaultValue: (any RequestMessaging)? = nil
}

extension EnvironmentValues {
    var requestMessagingService: (any RequestMessaging)? {
        get { self[RequestMessagingServiceKey.self] }
        set { self[RequestMessagingServiceKey.self] = newValue }
    }
}
