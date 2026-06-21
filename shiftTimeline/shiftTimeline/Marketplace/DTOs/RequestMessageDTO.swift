import Foundation

/// A chat message in a service-request thread (E12). Read from REST + realtime;
/// `sender_id` is the author (= auth.uid() on insert). `created_at` is the
/// pagination cursor and sort key.
nonisolated struct RequestMessageDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let requestID: UUID
    let senderID: UUID
    let body: String
    let createdAt: PostgresTimestamp

    enum CodingKeys: String, CodingKey {
        case id
        case requestID = "request_id"
        case senderID = "sender_id"
        case body
        case createdAt = "created_at"
    }
}

/// Insert payload. The client supplies `id` so an optimistic message and its
/// realtime echo share an id (dedupe), and `created_at` stays server-managed.
nonisolated struct RequestMessageInsert: Encodable, Equatable {
    let id: UUID
    let requestID: UUID
    let senderID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case id
        case requestID = "request_id"
        case senderID = "sender_id"
        case body
    }
}
