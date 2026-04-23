import Foundation

/// A single block's resolved rain probability, stored as part of a ``WeatherSnapshot``.
public struct BlockRainEntry: Codable, Sendable, Hashable {
    public let blockId: UUID
    /// Precipitation probability in the range 0.0–1.0.
    public let rainProbability: Double

    public init(blockId: UUID, rainProbability: Double) {
        self.blockId = blockId
        self.rainProbability = rainProbability
    }
}

/// Caches per-block rain probability data fetched from WeatherKit.
///
/// Stored as JSON-encoded `Data` on `EventModel.weatherSnapshot`.
/// The `isFresh` property gates both the service cache-skip and the UI banner.
public struct WeatherSnapshot: Codable, Sendable {
    /// Per-block resolved precipitation probabilities.
    public let entries: [BlockRainEntry]
    /// The time at which this snapshot was last fetched from WeatherKit.
    public let fetchedAt: Date

    public init(entries: [BlockRainEntry], fetchedAt: Date = Date()) {
        self.entries = entries
        self.fetchedAt = fetchedAt
    }

    /// Returns `true` if the snapshot was fetched less than 30 minutes ago.
    public var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 1800
    }

    /// Returns the subset of block IDs that are outdoor-tagged and have
    /// a `rainProbability > 0.5` in this snapshot.
    ///
    /// - Parameter blocks: Tuples of `(id: UUID, isOutdoor: Bool)` — pass
    ///   all blocks belonging to the event.
    /// - Returns: Matching `BlockRainEntry` values in the same order as `blocks`.
    public func atRiskEntries(for blocks: [(id: UUID, isOutdoor: Bool)]) -> [BlockRainEntry] {
        blocks
            .filter(\.isOutdoor)
            .compactMap { block in
                entries.first { $0.blockId == block.id && $0.rainProbability > 0.5 }
            }
    }
}
