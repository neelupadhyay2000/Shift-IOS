# UI Testing Guide

> SHIFT-1003.6 — How to add a screen to the page-object suite and write a test against it.

This document is the source-of-truth for the XCUITest suite that ships under [shiftTimelineUITests/](../shiftTimelineUITests). It describes the project structure, the page-object pattern, accessibility-identifier discipline, and the launch-argument protocol used to put the host app into a deterministic state.

---

## 1. Folder Layout

```
shiftTimelineUITests/
├── Helpers/          → Test infrastructure (SHIFTUITestCase, LaunchArgument, AccessibilityID mirror)
├── PageObjects/      → One Screen per primary destination (EventRosterScreen, TimelineScreen, …)
├── Suites/           → @MainActor test classes that drive flows via page objects
└── Fixtures/         → (Reserved) JSON or Swift fixture data referenced from tests
```

Every test file belongs in `Suites/`, every screen abstraction in `PageObjects/`. Helpers — base classes, launch-arg constants, and the test-target copy of `AccessibilityID` — live in `Helpers/`.

---

## 2. Architecture in One Diagram

```
┌──────────────────────┐    launchArguments      ┌────────────────────────┐
│  SHIFTUITestCase     │ ───────────────────────▶ │  shiftTimelineApp      │
│  (Helpers/)          │   -UITestMode 1          │  (host app)            │
│  ─ continueAfterFail │   -ResetData 1           │  ─ in-memory container │
│    = false           │   -SeedFixture <name>    │  ─ TestFixture.build() │
│  ─ app.launch()      │   -FrozenNow <iso8601>   │  ─ TestClock.now       │
└──────────┬───────────┘                          └──────────┬─────────────┘
           │                                                 │
           ▼                                                 ▼
┌──────────────────────┐                          ┌────────────────────────┐
│  Test Suite          │ ─── operates only on ───▶│  Page Objects          │
│  (Suites/Foo.swift)  │     typed page objects   │  (PageObjects/)        │
└──────────────────────┘                          └────────────────────────┘
```

Tests never touch raw `XCUIQuery`. Page objects never read `Date()`. The app reads launch args once at startup and freezes time + seeds data accordingly.

---

## 3. Anatomy of a Test

```swift
import XCTest

@MainActor
final class CreateEventFlowTests: SHIFTUITestCase {

    func testUserCanCreateEventFromRoster() throws {
        let roster = EventRosterScreen(app: app)
        roster.waitForExistence()

        roster.addEventButton.tap()

        let creation = EventCreationScreen(app: app)
        creation.waitForExistence()
        creation.titleField.typeText("Smith Wedding")
        creation.saveButton.tap()

        roster.assertVisible()
        XCTAssertTrue(roster.eventList.staticTexts["Smith Wedding"].exists)
    }
}
```

Three rules:
1. **Subclass `SHIFTUITestCase`** — never `XCTestCase` directly. The base class wires launch args, `continueAfterFailure = false`, and recreates the app per test.
2. **Drive the UI through page-object accessors** (`roster.addEventButton`, never `app.buttons["..."]`).
3. **Anchor each screen with `waitForExistence()` before asserting** — XCUITest does not implicitly wait.

---

## 4. Adding a New Screen

Follow these steps when a new feature ships a new top-level destination.

### 4.1 — Add identifiers to [`AccessibilityID`](../shiftTimeline/Design/AccessibilityID.swift)

Every interactive control on the new screen needs a stable identifier. Add a namespaced enum case:

```swift
enum AccessibilityID {
    enum Settings {
        static let navigationBar      = "settings.navBar"
        static let notificationsToggle = "settings.notifications.toggle"
        static let signOutButton       = "settings.signOut.button"
    }
}
```

Naming: `<screen>.<element>.<role>`, all camelCase, dot-delimited. Identifiers are **separate from VoiceOver labels** — keep them stable across localizations.

Mirror the same enum into [`shiftTimelineUITests/Helpers/AccessibilityID.swift`](../shiftTimelineUITests/Helpers/AccessibilityID.swift) so the test target can reference identical constants without importing the app target.

### 4.2 — Tag the SwiftUI views

Every `Button`, `TextField`, `Toggle`, `Picker`, list cell, sheet, alert, and tab on the new screen must carry `.accessibilityIdentifier(...)`:

```swift
Toggle("Notifications", isOn: $enabled)
    .accessibilityIdentifier(AccessibilityID.Settings.notificationsToggle)
```

The SwiftLint custom rule `accessibility_identifier_required` (in [.swiftlint.yml](../../.swiftlint.yml)) warns when a `Button`, `TextField`, or `Toggle` is missing one.

### 4.3 — Create the page object

Create `PageObjects/SettingsScreen.swift`:

```swift
import XCTest

@MainActor
final class SettingsScreen: BaseScreen {

    override var rootElement: XCUIElement {
        app.navigationBars[AccessibilityID.Settings.navigationBar]
    }

    var notificationsToggle: XCUIElement {
        app.switches[AccessibilityID.Settings.notificationsToggle]
    }

    var signOutButton: XCUIElement {
        app.buttons[AccessibilityID.Settings.signOutButton]
    }
}
```

Conventions:
- Subclass [`BaseScreen`](../shiftTimelineUITests/PageObjects/BaseScreen.swift), not the `Screen` protocol directly — `BaseScreen` provides `app` storage and the default `waitForExistence(timeout:)` / `assertVisible()` implementations.
- Override `rootElement` with the single anchor that proves the screen is on-screen (typically a `navigationBar`).
- Expose every interactive element as a computed `XCUIElement` property. No tests should touch raw `app.buttons[…]` calls.

### 4.4 — Write the suite

Create `Suites/SettingsTests.swift`:

```swift
@MainActor
final class SettingsTests: SHIFTUITestCase {
    func testToggleNotificationsPersists() throws {
        let settings = SettingsScreen(app: app)
        // navigate from roster → settings here …
        settings.waitForExistence()
        settings.notificationsToggle.tap()
        // assertions …
    }
}
```

---

## 5. Deterministic State: Launch Arguments

The host app honours these flags (see [LaunchArgument.swift](../shiftTimelineUITests/Helpers/LaunchArguments.swift)):

| Flag             | Purpose                                                                                              | Example                                  |
|------------------|------------------------------------------------------------------------------------------------------|------------------------------------------|
| `-UITestMode 1`  | Boots with an in-memory `ModelContainer`; disables CloudKit, Tips, Sunset prefetch, watch sync.      | Always set by `SHIFTUITestCase`.         |
| `-ResetData 1`   | Wipes `UserDefaults` and the App Group store before the first scene renders.                        | Always set by `SHIFTUITestCase`.         |
| `-SeedFixture`   | Builds the named [`TestFixture`](../SHIFT/SHIFTKit/Sources/TestSupport/TestFixture.swift) into the in-memory store at boot. | `-SeedFixture singleEventFiveBlocks`     |
| `-FrozenNow`     | Pins `TestClock.now` to an ISO 8601 instant so countdowns/timers are deterministic.                  | `-FrozenNow 2026-06-15T14:00:00Z`        |

To override launch args in a single test class, override `configureLaunch()`:

```swift
override func configureLaunch() {
    super.configureLaunch()
    app.launchArguments += [
        LaunchArgument.seedFixture, "weddingTemplateApplied",
        LaunchArgument.frozenNow, "2026-06-15T14:00:00Z",
    ]
}
```

Available fixtures are listed exhaustively in [`TestFixture.swift`](../SHIFT/SHIFTKit/Sources/TestSupport/TestFixture.swift). Adding a new fixture is a SHIFT-1002 task — see that ticket's subtasks before adding new builders.

---

## 6. Stability Rules (Read These Before Filing a Flake)

1. **Always wait, never sleep.** Use `waitForExistence(timeout:)`. Never `Thread.sleep` or `RunLoop.run(until:)`.
2. **Anchor every screen.** The first thing every test does after navigating should be `targetScreen.waitForExistence()`.
3. **One identifier per element, forever.** Renaming an `AccessibilityID` constant breaks every test that referenced it. Treat the enum like a public API.
4. **Don't read `Date()`.** All time-sensitive flows must be expressed against `-FrozenNow`.
5. **Don't depend on alphabetical order.** Tests run in randomized order on the `SHIFT UITests` scheme. Each test must be hermetic.
6. **Don't share fixture data across tests.** `SHIFTUITestCase` resets the app between tests; tests that rely on prior-test side-effects will pass locally and fail on CI.
7. **If a test fails intermittently, quarantine it.** Mark it `XCTSkip` with a Jira link, then investigate. Do not increase retries to mask flake.

---

## 7. Running the Suite

| Goal                | How                                                                            |
|---------------------|--------------------------------------------------------------------------------|
| Single test         | Cmd-U on the specific `func` in Xcode, or right-click → Run.                  |
| All UI tests        | Choose the `SHIFT UITests` scheme → Cmd-U.                                     |
| Specific suite      | Right-click the suite class in the navigator → Run.                            |
| Specific test plan  | Product → Test Plan → select a shard or the nightly plan, then Cmd-U.         |
| CI                  | Xcode Cloud runs all 4 PR shards in parallel on every PR. See Section 9.       |

> Per project rules: never run `xcodebuild` from the terminal. Always use Xcode.

---

## 8. Quarantine Policy (SHIFT-1005.4)

Flaky tests **must not block the merge train**. The quarantine process is:

1. **Identify the flake.** A test fails intermittently on CI (> 2 retries in 5 nightly runs).
2. **Quarantine it.** Add `try UITestQuarantine.skipIfPR(reason: "...", ticket: "SHIFT-NNNN")` as the **first statement** in the test body. This `XCTSkip`s it on PR workflows only.
3. **Register it.** Add a row to the registry table in [`UITestQuarantine.swift`](../shiftTimelineUITests/Helpers/UITestQuarantine.swift).
4. **Fix it.** Investigate on nightly builds (the quarantine skip does not fire on `nightly-full`).
5. **Graduate it.** After 5 consecutive green nightly runs, remove the `skipIfPR` call and the registry row.

For **unit tests** (Swift Testing), use `@Test(.tags(.quarantine))` — the tag is declared in [`Tag+Quarantine.swift`](../shiftTimelineTests/Tag+Quarantine.swift).

---

## 9. CI Integration (SHIFT-1005)

### Workflows

| Workflow        | Trigger           | Simulators                                  | Test plan(s)                       | Wall-time budget |
|-----------------|-------------------|---------------------------------------------|------------------------------------|-----------------|
| `pr-uitests`    | Every pull request | 4 × iPhone 16 (parallel)                   | shard-1, shard-2, shard-3, shard-4 | ≤ 8 min         |
| `nightly-full`  | Daily 02:00 UTC   | iPhone 16 + iPhone SE 3 + iPad Pro 13-inch  | nightly-full                       | ≤ 25 min        |

Workflow specs (source of truth for App Store Connect configuration):
- [`.xcode/workflows/pr-uitests.yml`](../../.xcode/workflows/pr-uitests.yml)
- [`.xcode/workflows/nightly-full.yml`](../../.xcode/workflows/nightly-full.yml)

### Sharding Strategy

The `pr-uitests` workflow shards the test suite across 4 parallel iPhone 16 simulators by **test class**. Each shard runs a non-overlapping set of classes:

| Shard | Test plan file               | Domain                    | Test classes (current → future)                                   |
|-------|------------------------------|---------------------------|-------------------------------------------------------------------|
| 1     | `pr-uitests-shard-1.xctestplan` | Foundation & Planning  | `AppLaunchSmokeTests`, `EventRosterTests`, `EventCreationTests`, `TemplatePickerTests` |
| 2     | `pr-uitests-shard-2.xctestplan` | Live Execution          | `LiveDashboardTests`, `ShiftMenuTests`, `BlockInspectorTests`     |
| 3     | `pr-uitests-shard-3.xctestplan` | Data, Sync & Vendors    | `VendorListTests`, `TimelineTests`, `SyncTests`, `PostEventReportTests` |
| 4     | `pr-uitests-shard-4.xctestplan` | E2E, A11y & Polish      | `EndToEndTests`, `PerformanceUITests`, `AccessibilityUITests`, `LocalizationUITests` |

**When adding a new test class:**
1. Decide which shard domain it belongs to.
2. Add the class name to that shard's `.xctestplan` (remove it from `skippedTests`).
3. Add the class name to all other shards' `skippedTests` arrays.
4. Test plan files live in `shiftTimeline/TestPlans/`.

### CI Scripts

Xcode Cloud hooks live in `ci_scripts/` at the repo root:

| Script                     | Phase              | Purpose                                                    |
|----------------------------|--------------------|------------------------------------------------------------|
| `ci_post_clone.sh`         | After clone        | Install SwiftFormat; gate on Xcode ≥ 16                    |
| `ci_pre_xcodebuild.sh`     | Before xcodebuild  | Validate test plan file exists; log shard assignment       |
| `ci_post_xcodebuild.sh`    | After xcodebuild   | Send Slack webhook on `nightly-full` failure               |

### Slack Notification

`ci_post_xcodebuild.sh` sends a `#shift-ci` Slack alert on nightly failure. Set the `SLACK_WEBHOOK_URL` secret in App Store Connect → `nightly-full` workflow → Environment → Variables (mark as **Secret**). Never commit the URL.

---

## 10. Reference

- Base test case → [SHIFTUITestCase.swift](../shiftTimelineUITests/Helpers/SHIFTUITestCase.swift)
- Launch arguments → [LaunchArguments.swift](../shiftTimelineUITests/Helpers/LaunchArguments.swift)
- Page-object protocol → [Screen.swift](../shiftTimelineUITests/PageObjects/Screen.swift) + [BaseScreen.swift](../shiftTimelineUITests/PageObjects/BaseScreen.swift)
- App-side identifiers → [AccessibilityID.swift](../shiftTimeline/Design/AccessibilityID.swift)
- Test-side identifier mirror → [AccessibilityID.swift](../shiftTimelineUITests/Helpers/AccessibilityID.swift)
- Fixtures → [TestFixture.swift](../SHIFT/SHIFTKit/Sources/TestSupport/TestFixture.swift), [Builders/](../SHIFT/SHIFTKit/Sources/TestSupport/Builders)
- Smoke test reference → [AppLaunchSmokeTests.swift](../shiftTimelineUITests/Suites/AppLaunchSmokeTests.swift)
- Epic spec → [JIRA_UI_TESTING_EPIC.md](../../JIRA_UI_TESTING_EPIC.md)
