import Foundation
import Models

@MainActor
extension TimeBlockModel {
    /// Projects this block to its wire form, reading `track_id` / `event_id`
    /// from the graph.
    /// - Throws: `ModelMappingError.missingTrack` / `.missingEvent` if detached.
    func toDTO() throws -> BlockDTO {
        guard let track else { throw ModelMappingError.missingTrack }
        guard let eventID = track.event?.id else { throw ModelMappingError.missingEvent }
        return toDTO(trackID: track.id, eventID: eventID)
    }

    /// Projects this block using explicitly supplied parent ids — used by the
    /// remote repository, which already knows the owning track and event.
    func toDTO(trackID: UUID, eventID: UUID) -> BlockDTO {
        BlockDTO(
            id: id,
            trackID: trackID,
            eventID: eventID,
            title: title,
            scheduledStart: PostgresTimestamp(scheduledStart),
            originalStart: PostgresTimestamp(originalStart),
            duration: duration,
            minimumDuration: minimumDuration,
            isPinned: isPinned,
            notes: notes,
            // E15 replaces this with a real Storage key; for now the local URL
            // string round-trips through `voice_memo_path`.
            voiceMemoPath: voiceMemoURL?.absoluteString,
            voiceMemoDuration: voiceMemoDuration,
            voiceMemoCreatedAt: PostgresTimestamp(voiceMemoCreatedAt),
            colorTag: colorTag,
            icon: icon,
            status: status.rawValue,
            requiresReview: requiresReview,
            isOutdoor: isOutdoor,
            venueAddress: venueAddress,
            venueName: venueName,
            blockLatitude: blockLatitude,
            blockLongitude: blockLongitude,
            isTransitBlock: isTransitBlock,
            completedTime: PostgresTimestamp(completedTime),
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }

    /// One `block_vendors` junction row per assigned vendor.
    /// - Throws: `ModelMappingError.missingEvent` if the block is detached.
    func blockVendorDTOs() throws -> [BlockVendorDTO] {
        guard let eventID = track?.event?.id else { throw ModelMappingError.missingEvent }
        return (vendors ?? []).map {
            BlockVendorDTO(blockID: id, eventVendorID: $0.id, eventID: eventID)
        }
    }

    /// One `block_dependencies` junction row per dependency edge (`self` depends
    /// on the listed block). The inverse `dependents` is reconstructed from these
    /// same rows, so only the forward edges are emitted.
    /// - Throws: `ModelMappingError.missingEvent` if the block is detached.
    func blockDependencyDTOs() throws -> [BlockDependencyDTO] {
        guard let eventID = track?.event?.id else { throw ModelMappingError.missingEvent }
        return (dependencies ?? []).map {
            BlockDependencyDTO(blockID: id, dependsOnBlockID: $0.id, eventID: eventID)
        }
    }

    /// Wires assigned vendors from the `block_vendors` rows addressed to this block.
    func linkVendors(_ junctions: [BlockVendorDTO], vendors: [UUID: VendorModel]) {
        self.vendors = junctions
            .filter { $0.blockID == id }
            .compactMap { vendors[$0.eventVendorID] }
    }

    /// Wires dependency edges from the `block_dependencies` rows addressed to this block.
    func linkDependencies(_ junctions: [BlockDependencyDTO], blocks: [UUID: TimeBlockModel]) {
        dependencies = junctions
            .filter { $0.blockID == id }
            .compactMap { blocks[$0.dependsOnBlockID] }
    }
}

@MainActor
extension BlockDTO {
    /// Builds a fresh `TimeBlockModel` with this row's scalar fields (relationships unwired).
    func makeModel() -> TimeBlockModel {
        let model = TimeBlockModel(
            title: title,
            scheduledStart: scheduledStart.value,
            originalStart: originalStart.value,
            duration: duration
        )
        apply(to: model)
        return model
    }

    /// Overwrites `model`'s scalar fields from this row (upsert by id).
    func apply(to model: TimeBlockModel) {
        model.id = id
        model.title = title
        model.scheduledStart = scheduledStart.value
        model.originalStart = originalStart.value
        model.duration = duration
        model.minimumDuration = minimumDuration
        model.isPinned = isPinned
        model.notes = notes
        model.voiceMemoURL = voiceMemoPath.flatMap { URL(string: $0) }
        model.voiceMemoDuration = voiceMemoDuration
        model.voiceMemoCreatedAt = voiceMemoCreatedAt?.value
        model.colorTag = colorTag
        model.icon = icon
        model.status = BlockStatus(rawValue: status) ?? .upcoming
        model.requiresReview = requiresReview
        model.isOutdoor = isOutdoor
        model.venueAddress = venueAddress
        model.venueName = venueName
        model.blockLatitude = blockLatitude ?? 0
        model.blockLongitude = blockLongitude ?? 0
        model.isTransitBlock = isTransitBlock
        model.completedTime = completedTime?.value
    }

    /// Wires the parent relationship by resolving `track_id` against `tracks`.
    func linkParent(_ model: TimeBlockModel, tracks: [UUID: TimelineTrack]) {
        model.track = tracks[trackID]
    }
}
