import XCTest

// MARK: - UITest Quarantine Registry (SHIFT-1005.4)
//
// Centralised list of UI tests that are quarantined (known-flaky).
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │  PR builds (workflow name starts with "pr-"):                               │
// │    Call `UITestQuarantine.skipIfPR(reason:)` at the top of the test body.  │
// │    The test is skipped via XCTSkip — it does not block the merge train.     │
// │                                                                             │
// │  Nightly builds (workflow name starts with "nightly-"):                     │
// │    The guard is not triggered. The test runs normally so the flake can be  │
// │    observed and fixed.                                                      │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ── Registering a Quarantined Test ────────────────────────────────────────────
//
//   1. Add a row to the registry table below.
//   2. Add `try UITestQuarantine.skipIfPR(reason: "...", ticket: "SHIFT-NNNN")` as
//      the *first statement* of the flaky test method.
//   3. Commit: "SHIFT-NNNN: quarantine <TestClass.testMethod>"
//
// ── Graduating a Test Out of Quarantine ────────────────────────────────────────
//
//   1. Verify 5 consecutive green nightly runs.
//   2. Remove the `skipIfPR` call from the test body.
//   3. Remove the row from the registry table below.
//   4. Commit: "SHIFT-NNNN: graduate <TestClass.testMethod> from quarantine"
//
// ─────────────────────────────────────────────────────────────────────────────
// Registry — currently quarantined tests
// ─────────────────────────────────────────────────────────────────────────────
//
//  Class                        | Method                       | Ticket     | Quarantined
//  ─────────────────────────────┼──────────────────────────────┼────────────┼────────────
//  (empty — no flakes yet)      |                              |            |
//
// ─────────────────────────────────────────────────────────────────────────────

enum UITestQuarantine {

    // MARK: - Skip Helper

    /// Skips the current test when running on a PR Xcode Cloud workflow.
    ///
    /// **Detection:** reads the `CI_WORKFLOW` environment variable injected by
    /// Xcode Cloud. If the workflow name starts with `"pr-"` the test is thrown
    /// as `XCTSkip`. On `"nightly-"` and local runs the call is a no-op, so the
    /// flaky test executes and its failure is visible for diagnosis.
    ///
    /// **Usage:**
    /// ```swift
    /// func testFlakyNavigation() throws {
    ///     try UITestQuarantine.skipIfPR(
    ///         reason: "3% timeout navigating to LiveDashboard on slow CI",
    ///         ticket: "SHIFT-1099"
    ///     )
    ///     // ... test body runs only on nightly / local
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - reason: Human-readable description of the flake.
    ///   - ticket: Jira ticket tracking the fix (e.g. `"SHIFT-1099"`).
    static func skipIfPR(
        reason: String,
        ticket: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let workflow = ProcessInfo.processInfo.environment["CI_WORKFLOW"] ?? ""
        guard workflow.hasPrefix("pr-") else { return }
        throw XCTSkip(
            "[\(ticket)] Quarantined on PR builds: \(reason)",
            file: file,
            line: line
        )
    }
}

// MARK: - Swift Testing Tag (unit test target companion)
//
// The `.quarantine` tag is used by *unit* tests written with Swift Testing
// (shiftTimelineTests target) to mark known-flaky async/service tests.
//
// Declaration lives in shiftTimelineTests/Tag+Quarantine.swift.
// Usage in a unit test:
//
//   @Test(.tags(.quarantine))
//   func someFlakyCKTest() async throws { ... }
//
// PR shards exclude tests tagged `.quarantine` via skippedTests in the test plan.
// Nightly runs include all tests — the quarantine tag is purely informational there.
//
// See: shiftTimeline/TestPlans/pr-uitests-shard-*.xctestplan
//      shiftTimeline/TestPlans/nightly-full.xctestplan
