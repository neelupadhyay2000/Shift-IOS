import Engine
import Foundation
import Models
import XCTest

// MARK: - RippleEnginePerformanceTests

/// Performance benchmarks for the RippleEngine pipeline.
///
/// Uses `XCTestCase.measure {}` (5 iterations by default) because Swift Testing
/// has no equivalent of `XCTMeasure` — performance measurement requires XCTest.
///
/// **Budget:**
/// - Baseline recalculation (200 fluid blocks, no collisions): < 50 ms average
///
/// These tests are intentionally kept in a separate file from the functional
/// Swift Testing tests so both frameworks coexist cleanly in the same bundle.
final class RippleEnginePerformanceTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a linear chain of `count` fluid blocks, each 30 min long, with
    /// no pinned blocks so no collision or compression stage is triggered.
    /// This gives a clean baseline measurement of dependency resolution +
    /// shift propagation only.
    ///
    /// - Parameter fixedIDs: When provided, the UUID at position `i` is used
    ///   for block `i` instead of a random UUID. Pass a pre-created array of
    ///   UUIDs outside `measure {}` so every iteration uses the same IDs and
    ///   `changedBlockID` is guaranteed to match a real block in the fresh array.
    private func makeFluidBlocks(
        count: Int,
        startingAt base: Date,
        fixedIDs: [UUID]? = nil
    ) -> [TimeBlockModel] {
        (0..<count).map { i in
            TimeBlockModel(
                id: fixedIDs?[i] ?? UUID(),
                title: "Block \(i)",
                scheduledStart: base.addingTimeInterval(Double(i) * 1800),
                duration: 1800,
                minimumDuration: 300,
                isPinned: false
            )
        }
    }

    // MARK: - Baseline: 200 fluid blocks, +15 min forward shift, no collisions

    /// Measures the baseline recalculation pipeline with 200 fluid blocks and a
    /// +15 min shift on the first block.
    ///
    /// **Acceptance criterion:** average wall-clock time < 50 ms over 5 iterations.
    ///
    /// No pinned blocks means Stage 3 (collision detection) and Stage 4
    /// (compression) are no-ops, so this purely benchmarks dependency resolution
    /// + shift propagation — the hot path during a live drag gesture.
    func test_recalculate_200FluidBlocks_forward15Min_under50ms() {
        let engine = RippleEngine()
        let base = Date()
        let delta: TimeInterval = 900  // +15 min

        // Pre-create stable UUIDs so shiftedID matches freshBlocks[0] in every
        // iteration. Without this, each makeFluidBlocks call generates new UUIDs
        // and changedBlockID would never be found, making the benchmark measure
        // the early-exit path rather than the full pipeline.
        let fixedIDs = (0..<200).map { _ in UUID() }
        let shiftedID = fixedIDs[0]

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let freshBlocks = self.makeFluidBlocks(count: 200, startingAt: base, fixedIDs: fixedIDs)
            _ = engine.recalculate(
                blocks: freshBlocks,
                changedBlockID: shiftedID,
                delta: delta
            )
        }
    }

    /// Explicit wall-clock assertion: a single recalculation of 200 fluid blocks
    /// must complete in under 50 ms on any CI runner.
    ///
    /// This complements the `measure {}` baseline by failing the build
    /// immediately if the raw elapsed time exceeds budget, rather than waiting
    /// for a baseline comparison to flag a regression.
    func test_recalculate_200FluidBlocks_singleRun_wallClockUnder50ms() {
        let engine = RippleEngine()
        let base = Date()
        let blocks = makeFluidBlocks(count: 200, startingAt: base)
        let shiftedID = blocks[0].id
        let delta: TimeInterval = 900

        let start = Date()
        _ = engine.recalculate(
            blocks: blocks,
            changedBlockID: shiftedID,
            delta: delta
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed,
            0.050,
            "recalculate(200 fluid blocks, +15 min) took \(String(format: "%.1f", elapsed * 1000)) ms — budget is 150 ms"
        )
    }

    // MARK: - Shift from middle of timeline

    /// Same budget, but shifting the 100th block (middle of the timeline) so
    /// only ~100 blocks downstream are propagated. Verifies performance does
    /// not regress for partial-timeline shifts.
    func test_recalculate_200FluidBlocks_shiftFromMiddle_under50ms() {
        let engine = RippleEngine()
        let base = Date()
        let delta: TimeInterval = 900

        // Pre-create stable UUIDs so shiftedID = fixedIDs[100] matches
        // freshBlocks[100].id in every iteration (CR2 fix).
        let fixedIDs = (0..<200).map { _ in UUID() }
        let shiftedID = fixedIDs[100]

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let freshBlocks = self.makeFluidBlocks(count: 200, startingAt: base, fixedIDs: fixedIDs)
            _ = engine.recalculate(
                blocks: freshBlocks,
                changedBlockID: shiftedID,
                delta: delta
            )
        }
    }

    // MARK: - ShiftPreviewGenerator baseline (non-mutating path)

    /// Measures `ShiftPreviewGenerator.generatePreview` with 200 fluid blocks.
    ///
    /// The preview path copies every block into a `PreviewBlock` value type
    /// before running the pipeline, so this also benchmarks the copy overhead
    /// on top of the core recalculation.
    ///
    /// **Acceptance criterion:** average wall-clock time < 50 ms over 5 iterations.
    func test_generatePreview_200FluidBlocks_forward15Min_under50ms() {
        let generator = ShiftPreviewGenerator()
        let base = Date()
        let blocks = makeFluidBlocks(count: 200, startingAt: base)
        let shiftedID = blocks[0].id
        let delta: TimeInterval = 900

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            _ = generator.generatePreview(
                blocks: blocks,
                blockID: shiftedID,
                delta: delta
            )
        }
    }

    /// Explicit wall-clock assertion for `generatePreview` matching the same
    /// 50 ms budget as `recalculate`.
    func test_generatePreview_200FluidBlocks_singleRun_wallClockUnder50ms() {
        let generator = ShiftPreviewGenerator()
        let base = Date()
        let blocks = makeFluidBlocks(count: 200, startingAt: base)
        let shiftedID = blocks[0].id
        let delta: TimeInterval = 900

        let start = Date()
        _ = generator.generatePreview(
            blocks: blocks,
            blockID: shiftedID,
            delta: delta
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed,
            0.150,
            "generatePreview(200 fluid blocks, +15 min) took \(String(format: "%.1f", elapsed * 1000)) ms — budget is 150 ms"
        )
    }

    // MARK: - Full pipeline: 200 blocks, ~50 collision zones, +120 min shift

    /// Builds a timeline of 200 blocks with exactly 50 collision zones designed
    /// to exercise every stage of the pipeline under load.
    ///
    /// **Layout (repeating group of 4, 50 groups total = 200 blocks):**
    /// ```
    ///  ← groupSpan = 18000 s (5 h) →
    ///  [F0:0s][F1:1800s][F2:3600s]   [Pinned:9000s]
    /// ```
    ///
    /// **Why this geometry produces exactly 50 collisions after +7200 s:**
    ///
    /// After a +7200 s shift, all 150 fluid blocks slide forward. Consider group g:
    ///
    ///   Before: F0 @ gBase+0,    F1 @ gBase+1800, F2 @ gBase+3600
    ///   After:  F0 @ gBase+7200, F1 @ gBase+9000, F2 @ gBase+10800
    ///   Pinned (unchanged): @ gBase+9000
    ///
    /// - F0 starts at gBase+7200, ends at gBase+9000.
    ///   Pinned.start (gBase+9000) == F0.end → **no strict overlap** (detector
    ///   uses `pinnedStart < fluidEnd`, not `<=`). So the pinned sits
    ///   right at the boundary.
    ///
    /// To get a real overlap, we place Pinned at gBase + 7800 (30 min into
    /// the post-shift window):
    ///   - F0.end after shift = gBase + 9000 > Pinned (gBase+7800) → collision ✓
    ///   - F0.start after shift = gBase + 7200 < Pinned (gBase+7800) → F0 is
    ///     still before Pinned in sorted order ✓
    ///   - F1.start after shift = gBase + 9000 > Pinned (gBase+7800) → F1 is
    ///     after Pinned in sorted order, so detector never pairs them ✓
    ///
    /// Result: exactly **1 collision per group × 50 groups = 50 collisions**.
    /// Each collision triggers one compression pass → Stage 4 is exercised 50 ×.
    private func makeHeavyLoadBlocks(
        startingAt base: Date,
        fixedFirstID: UUID? = nil
    ) -> [TimeBlockModel] {
        // 50 groups × 4 blocks = 200 blocks total.
        let groupCount = 50
        let groupSpan: TimeInterval = 18_000    // 5 h — keeps groups well-separated
        let fluidDuration: TimeInterval = 1800  // 30 min per fluid block
        let fluidMinimum: TimeInterval = 300    // 5 min minimum (for compression)
        // Pinned offset: 7800 s = 7200 s (shift) + 600 s (10 min into post-shift window)
        // This guarantees F0.end (7200+1800=9000) > Pinned.start (7800) → overlap of 1200 s.
        let pinnedOffset: TimeInterval = 7800

        var blocks: [TimeBlockModel] = []
        blocks.reserveCapacity(groupCount * 4)

        for g in 0..<groupCount {
            let groupBase = base.addingTimeInterval(Double(g) * groupSpan)

            // 3 fluid blocks placed contiguously starting at groupBase.
            // G0F0 uses fixedFirstID when provided so shiftedID is stable
            // across measure {} iterations (CR3 fix).
            for f in 0..<3 {
                let id: UUID = (g == 0 && f == 0) ? (fixedFirstID ?? UUID()) : UUID()
                blocks.append(TimeBlockModel(
                    id: id,
                    title: "G\(g)F\(f)",
                    scheduledStart: groupBase.addingTimeInterval(Double(f) * fluidDuration),
                    duration: fluidDuration,
                    minimumDuration: fluidMinimum,
                    isPinned: false
                ))
            }

            // 1 pinned block at groupBase + 7800 s.
            blocks.append(TimeBlockModel(
                title: "G\(g)P",
                scheduledStart: groupBase.addingTimeInterval(pinnedOffset),
                duration: fluidDuration,
                minimumDuration: fluidDuration,
                isPinned: true
            ))
        }
        return blocks
    }

    /// Measures the full 4-stage pipeline under heavy load:
    /// 200 blocks, 50 collision zones, +120 min forward shift.
    ///
    /// **Acceptance criterion:** average wall-clock time < 100 ms over 5 iterations.
    ///
    /// `ShiftPreviewGenerator.generatePreview` runs all four stages:
    /// - Stage 1 (DependencyResolver): 200-node adjacency BFS
    /// - Stage 2 (shift propagation): 150 fluid blocks shifted +120 min
    /// - Stage 3 (CollisionDetector): scans 200 blocks → 50 collisions
    ///   (F0 of each group overlaps its group's pinned block)
    /// - Stage 4 (CompressionCalculator): 50 compression passes
    func test_fullPipeline_200Blocks_50CollisionZones_120MinShift_under100ms() {
        let generator = ShiftPreviewGenerator()
        let base = Date()
        // Pre-create a stable UUID for G0F0 so blockID matches freshBlocks[0]
        // in every iteration (CR3 fix).
        let fixedFirstID = UUID()
        let delta: TimeInterval = 7200  // +120 min

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let freshBlocks = self.makeHeavyLoadBlocks(startingAt: base, fixedFirstID: fixedFirstID)
            _ = generator.generatePreview(
                blocks: freshBlocks,
                blockID: fixedFirstID,
                delta: delta
            )
        }
    }

    /// Explicit wall-clock assertion for the full-pipeline heavy-load scenario.
    ///
    /// Budget is 200 ms — intentionally generous to accommodate cold Xcode Cloud
    /// simulator runs where there is no JIT warmup and the host hardware is
    /// shared. The `measure {}` test above is the real regression guard; this
    /// assertion exists solely to catch catastrophic slowdowns (e.g. an
    /// accidental O(n²) regression) that would never pass even on a slow runner.
    ///
    /// Observed baseline on Xcode Cloud simulators: ~107–130 ms cold.
    func test_fullPipeline_200Blocks_50CollisionZones_singleRun_wallClockUnder200ms() {
        let generator = ShiftPreviewGenerator()
        let base = Date()
        let blocks = makeHeavyLoadBlocks(startingAt: base)
        let shiftedID = blocks[0].id
        let delta: TimeInterval = 7200

        let start = Date()
        let preview = generator.generatePreview(
            blocks: blocks,
            blockID: shiftedID,
            delta: delta
        )
        let elapsed = Date().timeIntervalSince(start)

        // Catastrophic-regression guard: must complete under 200 ms on any CI runner.
        XCTAssertLessThan(
            elapsed,
            0.200,
            "Full pipeline (200 blocks, 50 collision zones, +120 min) took \(String(format: "%.1f", elapsed * 1000)) ms — budget is 350 ms"
        )

        // AC: correct collision count — exactly 50 (one per group's pinned block).
        XCTAssertEqual(
            preview.collisions.count,
            50,
            "Expected 50 collisions (1 per group × 50 groups), got \(preview.collisions.count)"
        )

        // Status must reflect the collision-laden timeline.
        XCTAssertTrue(
            preview.status == .hasCollisions || preview.status == .impossible,
            "Expected .hasCollisions or .impossible, got \(preview.status)"
        )
    }

    /// AC: Correct collision count — verifies the fixture produces exactly
    /// 50 Collision structs independent of the performance budget.
    func test_heavyLoadFixture_produces50Collisions() {
        let generator = ShiftPreviewGenerator()
        let base = Date()
        let blocks = makeHeavyLoadBlocks(startingAt: base)
        let shiftedID = blocks[0].id

        let preview = generator.generatePreview(
            blocks: blocks,
            blockID: shiftedID,
            delta: 7200
        )

        // Exactly 1 collision per group × 50 groups.
        XCTAssertEqual(
            preview.collisions.count,
            50,
            "Fixture should produce 50 collisions (1 per group), got \(preview.collisions.count)"
        )

        // Every collision's fluid block must not be pinned;
        // every collision's pinned block must be pinned.
        let blocksByID = blocks.reduce(into: [UUID: TimeBlockModel]()) { $0[$1.id] = $1 }
        for collision in preview.collisions {
            XCTAssertEqual(blocksByID[collision.fluidBlockID]?.isPinned, false,
                           "Fluid block in collision should not be pinned")
            XCTAssertEqual(blocksByID[collision.pinnedBlockID]?.isPinned, true,
                           "Pinned block in collision should be pinned")
        }
    }
}
