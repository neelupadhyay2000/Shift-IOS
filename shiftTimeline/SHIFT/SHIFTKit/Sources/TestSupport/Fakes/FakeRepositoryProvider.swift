import Foundation
import Models
import Services

/// In-memory `RepositoryProviding` implementation for unit tests and SwiftUI
/// previews.
///
/// All five repositories are `FakeXxx` instances backed by plain Swift arrays —
/// no `ModelContext` or SwiftData container is needed.
///
/// ### SwiftUI preview usage
/// ```swift
/// #Preview {
///     CreateEventSheet()
///         .modelContainer(try! PersistenceController.forTesting())
///         .repositories(FakeRepositoryProvider())
/// }
/// ```
///
/// ### Swift Testing usage
/// ```swift
/// let provider = await FakeRepositoryProvider()
/// let eventRepo = provider.events as! FakeEventRepository
/// ```
@MainActor
public struct FakeRepositoryProvider: RepositoryProviding {

    public let events: any EventRepositing
    public let tracks: any TrackRepositing
    public let blocks: any BlockRepositing
    public let vendors: any VendorRepositing
    public let shiftRecords: any ShiftRecordRepositing

    public init() {
        events = FakeEventRepository()
        tracks = FakeTrackRepository()
        blocks = FakeBlockRepository()
        vendors = FakeVendorRepository()
        shiftRecords = FakeShiftRecordRepository()
    }
}
