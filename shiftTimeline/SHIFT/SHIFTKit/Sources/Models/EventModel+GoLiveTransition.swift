import Foundation

public extension EventModel {
    /// Applies all in-memory state changes for the `.planning` → `.live` transition.
    ///
    /// - Sets `status` to `.live` and stamps `wentLiveAt`.
    /// - Resets every non-completed block to `.upcoming`.
    /// - Sets the chronologically-first non-completed block to `.active`.
    ///
    /// No I/O — no context save, no analytics, no watch/widget side-effects.
    /// Callers are responsible for saving the context and triggering any
    /// downstream side-effects after this call returns.
    ///
    /// - Parameter now: Wall-clock time of the transition. Defaults to `Date.now`;
    ///   inject a fixed value in tests for deterministic assertions.
    func applyGoLiveMutation(now: Date = .now) {
        let allBlocks = (tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        status = .live
        wentLiveAt = now

        for block in allBlocks where block.status != .completed {
            block.status = .upcoming
        }

        allBlocks.first(where: { $0.status != .completed })?.status = .active
    }
}
