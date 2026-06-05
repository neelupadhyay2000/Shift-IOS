import Foundation
import Services
import SwiftData

/// `RepositoryProviding` bundle that writes every mutation through to **both**
/// the local SwiftData store and Supabase while online.
///
/// Compose it from the local and remote providers plus the shared
/// `ModelContext`:
/// ```swift
/// let local = SwiftDataRepositoryProvider(context: context)
/// let remote = SupabaseRepositoryProvider(client: client) { authService.currentProfileID }
/// let provider = WriteThroughRepositoryProvider(context: context, local: local, remote: remote)
/// ```
@MainActor
struct WriteThroughRepositoryProvider: RepositoryProviding {
    let events: any EventRepositing
    let tracks: any TrackRepositing
    let blocks: any BlockRepositing
    let vendors: any VendorRepositing
    let shiftRecords: any ShiftRecordRepositing

    init(
        context: ModelContext,
        local: any RepositoryProviding,
        remote: any RepositoryProviding
    ) {
        let coordinator = WriteThroughCoordinator(context: context, remote: remote)
        events = WriteThroughEventRepository(local: local.events, remote: remote.events, coordinator: coordinator)
        tracks = WriteThroughTrackRepository(local: local.tracks, remote: remote.tracks, coordinator: coordinator)
        blocks = WriteThroughBlockRepository(local: local.blocks, remote: remote.blocks, coordinator: coordinator)
        vendors = WriteThroughVendorRepository(local: local.vendors, remote: remote.vendors, coordinator: coordinator)
        shiftRecords = WriteThroughShiftRecordRepository(
            local: local.shiftRecords,
            remote: remote.shiftRecords,
            coordinator: coordinator
        )
    }
}
