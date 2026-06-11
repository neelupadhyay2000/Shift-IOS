import Foundation
import Services
@testable import shiftTimeline
import Testing

/// Structural tests proving each Supabase repository satisfies its repository protocol
/// (so the app can swap the local provider for the remote one). The network
/// round-trip is exercised by the epic's online acceptance, not here — this
/// mirrors `SupabaseProfileRepositoryTests`, which also tests conformance only.
@Suite("Supabase repositories — protocol conformance")
@MainActor
struct SupabaseRepositoryConformanceTests {

    private func makeProvider() throws -> SupabaseClientProvider {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        return SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
    }

    @Test("SupabaseEventRepository conforms to EventRepositing")
    func eventRepo() throws {
        let repo: any EventRepositing = SupabaseEventRepository(
            client: try makeProvider().client,
            currentOwnerID: { nil }
        )
        _ = repo
    }

    @Test("SupabaseTrackRepository conforms to TrackRepositing")
    func trackRepo() throws {
        let repo: any TrackRepositing = SupabaseTrackRepository(client: try makeProvider().client)
        _ = repo
    }

    @Test("SupabaseBlockRepository conforms to BlockRepositing")
    func blockRepo() throws {
        let repo: any BlockRepositing = SupabaseBlockRepository(client: try makeProvider().client)
        _ = repo
    }

    @Test("SupabaseVendorRepository conforms to VendorRepositing")
    func vendorRepo() throws {
        let repo: any VendorRepositing = SupabaseVendorRepository(client: try makeProvider().client)
        _ = repo
    }

    @Test("SupabaseShiftRecordRepository conforms to ShiftRecordRepositing")
    func shiftRecordRepo() throws {
        let repo: any ShiftRecordRepositing = SupabaseShiftRecordRepository(client: try makeProvider().client)
        _ = repo
    }

    @Test("SupabaseRepositoryProvider conforms to RepositoryProviding and vends all five")
    func provider() throws {
        let provider: any RepositoryProviding = SupabaseRepositoryProvider(
            client: try makeProvider().client,
            currentOwnerID: { nil }
        )
        // Touch each vended repository so the bundle is fully exercised.
        _ = provider.events
        _ = provider.tracks
        _ = provider.blocks
        _ = provider.vendors
        _ = provider.shiftRecords
    }
}
