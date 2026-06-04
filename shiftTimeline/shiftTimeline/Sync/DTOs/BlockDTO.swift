import Foundation

/// Row in the Supabase `blocks` table. Mirrors `TimeBlockModel`.
///
/// `event_id` is denormalized (also present on the parent track) so RLS and
/// Realtime can filter by event without a join. `track_id` / `event_id` carry
/// the relationships; assignment and dependency edges live in the
/// `block_vendors` / `block_dependencies` junction tables.
///
/// `status` is coded as plain text (free-text column); the typed `BlockStatus`
/// conversion happens in the mapping layer (SHIFT-590). `voice_memo_path` is a
/// Supabase Storage key, not a local file URL.
nonisolated struct BlockDTO: Codable, Equatable {
    let id: UUID
    let trackID: UUID
    let eventID: UUID
    let title: String
    let scheduledStart: PostgresTimestamp
    let originalStart: PostgresTimestamp
    let duration: Double
    let minimumDuration: Double
    let isPinned: Bool
    let notes: String
    let voiceMemoPath: String?
    let voiceMemoDuration: Double?
    let voiceMemoCreatedAt: PostgresTimestamp?
    let colorTag: String
    let icon: String
    let status: String
    let requiresReview: Bool
    let isOutdoor: Bool
    let venueAddress: String
    let venueName: String
    let blockLatitude: Double?
    let blockLongitude: Double?
    let isTransitBlock: Bool
    let completedTime: PostgresTimestamp?
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case trackID = "track_id"
        case eventID = "event_id"
        case title
        case scheduledStart = "scheduled_start"
        case originalStart = "original_start"
        case duration
        case minimumDuration = "minimum_duration"
        case isPinned = "is_pinned"
        case notes
        case voiceMemoPath = "voice_memo_path"
        case voiceMemoDuration = "voice_memo_duration"
        case voiceMemoCreatedAt = "voice_memo_created_at"
        case colorTag = "color_tag"
        case icon
        case status
        case requiresReview = "requires_review"
        case isOutdoor = "is_outdoor"
        case venueAddress = "venue_address"
        case venueName = "venue_name"
        case blockLatitude = "block_latitude"
        case blockLongitude = "block_longitude"
        case isTransitBlock = "is_transit_block"
        case completedTime = "completed_time"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        trackID: UUID,
        eventID: UUID,
        title: String,
        scheduledStart: PostgresTimestamp,
        originalStart: PostgresTimestamp,
        duration: Double,
        minimumDuration: Double,
        isPinned: Bool,
        notes: String,
        voiceMemoPath: String? = nil,
        voiceMemoDuration: Double? = nil,
        voiceMemoCreatedAt: PostgresTimestamp? = nil,
        colorTag: String,
        icon: String,
        status: String,
        requiresReview: Bool,
        isOutdoor: Bool,
        venueAddress: String,
        venueName: String,
        blockLatitude: Double? = nil,
        blockLongitude: Double? = nil,
        isTransitBlock: Bool,
        completedTime: PostgresTimestamp? = nil,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.eventID = eventID
        self.title = title
        self.scheduledStart = scheduledStart
        self.originalStart = originalStart
        self.duration = duration
        self.minimumDuration = minimumDuration
        self.isPinned = isPinned
        self.notes = notes
        self.voiceMemoPath = voiceMemoPath
        self.voiceMemoDuration = voiceMemoDuration
        self.voiceMemoCreatedAt = voiceMemoCreatedAt
        self.colorTag = colorTag
        self.icon = icon
        self.status = status
        self.requiresReview = requiresReview
        self.isOutdoor = isOutdoor
        self.venueAddress = venueAddress
        self.venueName = venueName
        self.blockLatitude = blockLatitude
        self.blockLongitude = blockLongitude
        self.isTransitBlock = isTransitBlock
        self.completedTime = completedTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
