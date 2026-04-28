import Foundation
import SwiftData

/// Contract that every test fixture builder must satisfy.
///
/// Conforming types insert a complete, self-contained SwiftData model graph
/// into the provided `ModelContext`. The `clock` parameter supplies the base
/// timestamp; **builders must never call `Date()` directly**.
public protocol FixtureBuilding {

    /// Insert the complete fixture model graph into `context`.
    ///
    /// - Parameters:
    ///   - context: The SwiftData `ModelContext` receiving the fixture data.
    ///   - clock: Base timestamp. All `Date` values must derive from `clock.now`.
    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws
}
