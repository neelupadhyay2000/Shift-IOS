import Foundation
import Models
import SwiftData

// MARK: - RepositoryProviding

/// Groups all five repository protocols into a single injectable bundle.
///
/// Conformers supply one concrete implementation per aggregate. The
/// `SwiftDataRepositoryProvider` is used in production; `FakeRepositoryProvider`
/// (in TestSupport) is used in unit tests and SwiftUI previews.
///
/// Injection: apply `.repositories(myProvider)` on any SwiftUI view tree.
@MainActor
public protocol RepositoryProviding {
    var events: any EventRepositing { get }
    var tracks: any TrackRepositing { get }
    var blocks: any BlockRepositing { get }
    var vendors: any VendorRepositing { get }
    var shiftRecords: any ShiftRecordRepositing { get }
}

// MARK: - SwiftDataRepositoryProvider

/// Production implementation — all five repositories backed by the shared
/// `ModelContext` from the app's SwiftData container.
@MainActor
public struct SwiftDataRepositoryProvider: RepositoryProviding {
    public let events: any EventRepositing
    public let tracks: any TrackRepositing
    public let blocks: any BlockRepositing
    public let vendors: any VendorRepositing
    public let shiftRecords: any ShiftRecordRepositing

    public init(context: ModelContext) {
        events = SwiftDataEventRepository(context: context)
        tracks = SwiftDataTrackRepository(context: context)
        blocks = SwiftDataBlockRepository(context: context)
        vendors = SwiftDataVendorRepository(context: context)
        shiftRecords = SwiftDataShiftRecordRepository(context: context)
    }
}
