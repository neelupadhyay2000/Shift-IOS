import Foundation

/// Planned-vs-actual block timing report for a completed event. Codable for SwiftData/CloudKit storage.
public struct PostEventReport: Codable, Sendable, Equatable {

    /// Chronological entries per block. Incomplete blocks carry `actualCompletion == nil` and zero delta.
    public var entries: [BlockReportEntry]

    /// Sum of `deltaMinutes` across completed blocks. Positive = late, negative = early.
    public var totalDriftMinutes: Int

    /// Number of `ShiftRecord`s stamped during execution.
    public var totalShiftCount: Int

    /// When the report was generated.
    public var generatedAt: Date

    public init(
        entries: [BlockReportEntry],
        totalDriftMinutes: Int,
        totalShiftCount: Int,
        generatedAt: Date
    ) {
        self.entries = entries
        self.totalDriftMinutes = totalDriftMinutes
        self.totalShiftCount = totalShiftCount
        self.generatedAt = generatedAt
    }
}

/// Per-block row in a `PostEventReport`.
public struct BlockReportEntry: Codable, Sendable, Equatable {

    public var blockID: UUID           // stable reference back into the timeline
    public var blockTitle: String      // title at report-build time
    public var plannedStart: Date      // `originalStart` before any shifts
    public var actualCompletion: Date? // `completedTime`; nil if block was never completed
    public var deltaMinutes: Int       // positive = late, negative = early; 0 when nil

    public init(
        blockID: UUID,
        blockTitle: String,
        plannedStart: Date,
        actualCompletion: Date?,
        deltaMinutes: Int
    ) {
        self.blockID = blockID
        self.blockTitle = blockTitle
        self.plannedStart = plannedStart
        self.actualCompletion = actualCompletion
        self.deltaMinutes = deltaMinutes
    }
}
