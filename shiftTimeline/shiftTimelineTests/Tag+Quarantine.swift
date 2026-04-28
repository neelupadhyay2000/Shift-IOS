import Testing

// MARK: - Quarantine Tag (SHIFT-1005.4)
//
// Marks a Swift Testing unit test as quarantined (known-flaky).
//
// ┌──────────────────────────────────────────────────────────────────────────────┐
// │  PR builds: quarantined tests are tracked and excluded via test plans.       │
// │  Nightly builds: all tests including @Test(.tags(.quarantine)) run normally. │
// └──────────────────────────────────────────────────────────────────────────────┘
//
// Usage:
//   @Test(.tags(.quarantine))
//   func someFlakyCKTest() async throws { ... }
//
// Registry + graduation policy: see shiftTimelineUITests/Helpers/UITestQuarantine.swift

extension Tag {
    /// Applied to unit tests that are known-flaky and under active investigation.
    ///
    /// - PR runs exclude tests with this tag via `skippedTests` in the PR shard plans.
    /// - Nightly `nightly-full.xctestplan` includes all tags for monitoring.
    @Tag static var quarantine: Self
}
