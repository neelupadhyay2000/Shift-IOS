import Foundation
import Services
import Supabase

/// `RepositoryProviding` bundle backed by Supabase — the remote analogue of
/// `SwiftDataRepositoryProvider`. Lets the app swap the persistence backend by
/// injecting a different provider.
///
/// `currentOwnerID` resolves the signed-in profile id for `events.owner_id`
/// (typically `{ authService.currentProfileID }`).
@MainActor
struct SupabaseRepositoryProvider: RepositoryProviding {
    let events: any EventRepositing
    let tracks: any TrackRepositing
    let blocks: any BlockRepositing
    let vendors: any VendorRepositing
    let shiftRecords: any ShiftRecordRepositing

    init(client: SupabaseClient, currentOwnerID: @escaping @MainActor () -> UUID?) {
        events = SupabaseEventRepository(client: client, currentOwnerID: currentOwnerID)
        tracks = SupabaseTrackRepository(client: client)
        blocks = SupabaseBlockRepository(client: client)
        vendors = SupabaseVendorRepository(client: client)
        shiftRecords = SupabaseShiftRecordRepository(client: client)
    }
}
