import Foundation
import Services
import SwiftData

/// `RepositoryProviding` bundle that writes every mutation to the local
/// SwiftData store and appends an ``OutboxEntry`` for the offline SyncEngine to
/// replay. This is the offline-first production write path: writes never touch
/// the network synchronously. The remote half lives in the flush, which drains
/// the queue FIFO when connectivity returns.
///
/// Compose it from the local provider plus the current-profile resolver used to
/// stamp `events.owner_id` into enqueued payloads:
/// ```swift
/// let local = SwiftDataRepositoryProvider(context: context)
/// let provider = OutboxRepositoryProvider(
///     context: context,
///     local: local,
///     currentOwnerID: { authService.currentProfileID }
/// )
/// ```
@MainActor
struct OutboxRepositoryProvider: RepositoryProviding {
    let events: any EventRepositing
    let tracks: any TrackRepositing
    let blocks: any BlockRepositing
    let vendors: any VendorRepositing
    let shiftRecords: any ShiftRecordRepositing

    init(
        context: ModelContext,
        local: any RepositoryProviding,
        currentOwnerID: @escaping @MainActor () -> UUID?,
        diagnostics: SyncDiagnosticsCenter = .shared,
        onEnqueue: @escaping @MainActor () -> Void = {}
    ) {
        let coordinator = OutboxCoordinator(
            context: context,
            currentOwnerID: currentOwnerID,
            diagnostics: diagnostics,
            onEnqueue: onEnqueue
        )
        events = OutboxEventRepository(local: local.events, coordinator: coordinator)
        tracks = OutboxTrackRepository(local: local.tracks, coordinator: coordinator)
        blocks = OutboxBlockRepository(local: local.blocks, coordinator: coordinator)
        vendors = OutboxVendorRepository(local: local.vendors, coordinator: coordinator)
        shiftRecords = OutboxShiftRecordRepository(local: local.shiftRecords, coordinator: coordinator)
    }
}
