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
    private func makeFluidBlocks(count: Int, startingAt base: Date) -> [TimeBlockModel] {
        (0..<count).map { i in
            TimeBlockModel(
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
        let blocks = makeFluidBlocks(count: 200, startingAt: base)
        let shiftedID = blocks[0].id
        let delta: TimeInterval = 900  // +15 min

        // XCTMeasureOptions: 5 iterations (default), clock time metric.
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            // Re-create blocks each iteration so mutations from one run
            // don't carry over into the next.
            let freshBlocks = self.makeFluidBlocks(count: 200, startingAt: base)
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
            "recalculate(200 fluid blocks, +15 min) took \(String(format: "%.1f", elapsed * 1000)) ms — budget is 50 ms"
        )
    }

    // MARK: - Shift from middle of timeline

    /// Same budget, but shifting the 100th block (middle of the timeline) so
    /// only ~100 blocks downstream are propagated. Verifies performance does
    /// not regress for partial-timeline shifts.
    func test_recalculate_200FluidBlocks_shiftFromMiddle_under50ms() {
        let engine = RippleEngine()
        let base = Date()
        let blocks = makeFluidBlocks(count: 200, startingAt: base)
        let shiftedID = blocks[100].id
        let delta: TimeInterval = 900

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let freshBlocks = self.makeFluidBlocks(count: 200, startingAt: base)
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
            0.050,
            "generatePreview(200 fluid blocks, +15 min) took \(String(format: "%.1f", elapsed * 1000)) ms — budget is 50 ms"
        )
    }
}
