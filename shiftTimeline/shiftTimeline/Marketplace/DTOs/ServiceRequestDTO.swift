import Foundation

// MARK: - Status

/// service_requests.status values (matches the DB CHECK). Display strings live
/// with the UI.
enum ServiceRequestStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case declined
    case cancelled
}

// MARK: - Requested block snapshot

/// One element of the `requested_blocks` jsonb snapshot: enough for the vendor to
/// render the request WITHOUT event access pre-accept. `block_id` is what the
/// respond RPC validates against live blocks on accept.
nonisolated struct RequestedBlockDTO: Codable, Equatable, Identifiable {
    let blockID: UUID
    let title: String
    let start: PostgresTimestamp
    let end: PostgresTimestamp

    var id: UUID { blockID }

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case title
        case start
        case end
    }
}

// MARK: - Read DTO

/// Row in `service_requests` (read). The vendor decodes this for the inbox, the
/// planner for the outbox.
nonisolated struct ServiceRequestDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let eventID: UUID
    let plannerID: UUID
    let vendorProfileID: UUID
    let status: String
    let note: String?
    let requestedBlocks: [RequestedBlockDTO]
    let eventTitle: String
    let eventDate: PostgresTimestamp?
    let responseMessage: String?
    let respondedAt: PostgresTimestamp?
    let eventVendorID: UUID?
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case plannerID = "planner_id"
        case vendorProfileID = "vendor_profile_id"
        case status
        case note
        case requestedBlocks = "requested_blocks"
        case eventTitle = "event_title"
        case eventDate = "event_date"
        case responseMessage = "response_message"
        case respondedAt = "responded_at"
        case eventVendorID = "event_vendor_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var typedStatus: ServiceRequestStatus? { ServiceRequestStatus(rawValue: status) }
}

// MARK: - Insert payload

/// Write payload for creating a request. `status` is server-defaulted to pending;
/// timestamps are server-managed. Synthesized Encodable omits nil note/event_date.
nonisolated struct ServiceRequestInsert: Encodable, Equatable {
    let eventID: UUID
    let plannerID: UUID
    let vendorProfileID: UUID
    let note: String?
    let requestedBlocks: [RequestedBlockDTO]
    let eventTitle: String
    let eventDate: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case plannerID = "planner_id"
        case vendorProfileID = "vendor_profile_id"
        case note
        case requestedBlocks = "requested_blocks"
        case eventTitle = "event_title"
        case eventDate = "event_date"
    }
}

// MARK: - RPC result

/// Return shape of the `respond_to_service_request` RPC.
nonisolated struct ServiceRequestResponseDTO: Decodable, Equatable {
    let requestID: UUID
    let status: String
    let eventVendorID: UUID?
    let assignedBlocksCount: Int

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case eventVendorID = "event_vendor_id"
        case assignedBlocksCount = "assigned_blocks_count"
    }
}

/// Typed params for the respond RPC (wire keys match the SQL arg names).
nonisolated struct RespondRequestParams: Encodable, Equatable {
    let pRequestID: UUID
    let pAccept: Bool
    let pMessage: String?

    enum CodingKeys: String, CodingKey {
        case pRequestID = "p_request_id"
        case pAccept = "p_accept"
        case pMessage = "p_message"
    }
}
