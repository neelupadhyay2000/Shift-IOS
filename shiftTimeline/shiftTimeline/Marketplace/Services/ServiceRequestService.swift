import Foundation
import Models
import Services
import Supabase
import SwiftData
import SwiftUI

// MARK: - Protocol

/// Planner→vendor service requests (E11). Online-only direct Supabase access, like
/// the other marketplace services — but `respond(accept:)` bridges into the
/// existing sync stack: on accept it triggers a full re-hydrate (the same path as
/// an invite claim) so the newly-shared event appears in the vendor's Events tab.
protocol ServiceRequesting: Sendable {
    /// Creates a request: snapshots the event title/date + the selected blocks
    /// (from local SwiftData) into the row so the vendor can render it pre-accept.
    @discardableResult
    func createRequest(eventID: UUID, vendorProfileID: UUID, blockIDs: [UUID], note: String) async throws -> ServiceRequestDTO

    /// Vendor inbox: requests addressed to me (paginated, newest first).
    func inbox(limit: Int, offset: Int) async throws -> [ServiceRequestDTO]

    /// Planner outbox: my requests for a given event (paginated, newest first).
    func outbox(eventID: UUID, limit: Int, offset: Int) async throws -> [ServiceRequestDTO]

    /// Vendor accept/decline via the respond RPC. On accept, re-hydrates so the
    /// event lands in the vendor's Events tab.
    @discardableResult
    func respond(requestID: UUID, accept: Bool, message: String?) async throws -> ServiceRequestResponseDTO

    /// Planner cancels a pending request (status→cancelled, allowed by RLS).
    func cancel(requestID: UUID) async throws
}

// MARK: - Supabase implementation

@MainActor
struct ServiceRequestService: ServiceRequesting {
    private let client: SupabaseClient
    private let modelContainer: ModelContainer
    /// Re-hydrate hook (the sync stack's full refresh); nil in tests / flag-off.
    private let syncStack: SupabaseSyncStack?

    init(client: SupabaseClient, modelContainer: ModelContainer, syncStack: SupabaseSyncStack?) {
        self.client = client
        self.modelContainer = modelContainer
        self.syncStack = syncStack
    }

    // MARK: Create

    @discardableResult
    func createRequest(
        eventID: UUID,
        vendorProfileID: UUID,
        blockIDs: [UUID],
        note: String
    ) async throws -> ServiceRequestDTO {
        let plannerID = try await client.auth.session.user.id
        let snapshot = Self.resolveSnapshot(
            eventID: eventID,
            blockIDs: blockIDs,
            context: modelContainer.mainContext
        )
        let payload = ServiceRequestInsert(
            eventID: eventID,
            plannerID: plannerID,
            vendorProfileID: vendorProfileID,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            requestedBlocks: snapshot.blocks,
            eventTitle: snapshot.eventTitle,
            eventDate: snapshot.eventDate.map { PostgresTimestamp($0) }
        )
        return try await client
            .from("service_requests")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: Read

    func inbox(limit: Int = 20, offset: Int = 0) async throws -> [ServiceRequestDTO] {
        let uid = try await client.auth.session.user.id
        return try await client
            .from("service_requests")
            .select()
            .eq("vendor_profile_id", value: uid.uuidString)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .range(from: max(0, offset), to: max(0, offset) + max(1, limit) - 1)
            .execute()
            .value
    }

    func outbox(eventID: UUID, limit: Int = 20, offset: Int = 0) async throws -> [ServiceRequestDTO] {
        // RLS (sr_planner_select) already scopes to planner_id = auth.uid().
        try await client
            .from("service_requests")
            .select()
            .eq("event_id", value: eventID.uuidString)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .range(from: max(0, offset), to: max(0, offset) + max(1, limit) - 1)
            .execute()
            .value
    }

    // MARK: Respond / cancel

    @discardableResult
    func respond(requestID: UUID, accept: Bool, message: String?) async throws -> ServiceRequestResponseDTO {
        let params = RespondRequestParams(
            pRequestID: requestID,
            pAccept: accept,
            pMessage: message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
        let rows: [ServiceRequestResponseDTO] = try await client
            .rpc("respond_to_service_request", params: params)
            .execute()
            .value
        guard let result = rows.first else {
            throw ServiceRequestError.emptyResponse
        }
        // On accept, the claimed event_vendors row turns on can_access_event(); a
        // full re-hydrate (same path as invite claim) pulls the event into the
        // vendor's local store so it appears in the Events tab.
        if accept {
            await syncStack?.refresh()
        }
        return result
    }

    func cancel(requestID: UUID) async throws {
        try await client
            .from("service_requests")
            .update(["status": "cancelled"])
            .eq("id", value: requestID.uuidString)
            .execute()
    }

    // MARK: - Pure snapshot builder (unit-tested)

    /// Lightweight, Sendable source for one block's snapshot (decoupled from the
    /// SwiftData model so the builder is testable without a ModelContainer).
    struct BlockSnapshotSource: Sendable, Equatable {
        let id: UUID
        let title: String
        let scheduledStart: Date
        let duration: TimeInterval
    }

    /// Pure: maps block sources to the requested_blocks snapshot, computing each
    /// block's end as start + duration, preserving input order. `nonisolated` so
    /// it's synchronously callable (tests + the MainActor read path).
    nonisolated static func requestedBlocks(from sources: [BlockSnapshotSource]) -> [RequestedBlockDTO] {
        sources.map { source in
            RequestedBlockDTO(
                blockID: source.id,
                title: source.title,
                start: PostgresTimestamp(source.scheduledStart),
                end: PostgresTimestamp(source.scheduledStart.addingTimeInterval(source.duration))
            )
        }
    }

    // MARK: - SwiftData snapshot read

    struct ResolvedSnapshot: Sendable {
        let eventTitle: String
        let eventDate: Date?
        let blocks: [RequestedBlockDTO]
    }

    /// Reads the event title/date and the selected blocks from local SwiftData,
    /// preserving `blockIDs` order and skipping any that aren't present.
    @MainActor
    static func resolveSnapshot(eventID: UUID, blockIDs: [UUID], context: ModelContext) -> ResolvedSnapshot {
        let eventDescriptor = FetchDescriptor<EventModel>(predicate: #Predicate { $0.id == eventID })
        let event = try? context.fetch(eventDescriptor).first

        let selectedIDs = blockIDs
        let blockDescriptor = FetchDescriptor<TimeBlockModel>(predicate: #Predicate { selectedIDs.contains($0.id) })
        let fetched = (try? context.fetch(blockDescriptor)) ?? []
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Preserve the planner's selection order; skip blocks not found locally.
        let sources: [BlockSnapshotSource] = blockIDs.compactMap { id in
            guard let block = byID[id] else { return nil }
            return BlockSnapshotSource(
                id: block.id, title: block.title,
                scheduledStart: block.scheduledStart, duration: block.duration
            )
        }
        return ResolvedSnapshot(
            eventTitle: event?.title ?? "",
            eventDate: event?.date,
            blocks: requestedBlocks(from: sources)
        )
    }
}

enum ServiceRequestError: Error {
    case emptyResponse
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

// MARK: - Environment

private struct ServiceRequestServiceKey: EnvironmentKey {
    static let defaultValue: (any ServiceRequesting)? = nil
}

extension EnvironmentValues {
    var serviceRequestService: (any ServiceRequesting)? {
        get { self[ServiceRequestServiceKey.self] }
        set { self[ServiceRequestServiceKey.self] = newValue }
    }
}
