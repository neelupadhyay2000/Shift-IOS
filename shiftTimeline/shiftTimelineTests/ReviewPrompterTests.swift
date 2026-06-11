import Foundation
import Testing
@testable import shiftTimeline

/// Covers the once-per-app-version gate around the App Store review request.
struct ReviewPrompterTests {

    @Test func requestsWhenNeverPrompted() {
        #expect(ReviewPrompter.shouldRequest(lastPromptedVersion: nil, currentVersion: "1.0"))
    }

    @Test func doesNotRequestTwiceForSameVersion() {
        #expect(!ReviewPrompter.shouldRequest(lastPromptedVersion: "1.0", currentVersion: "1.0"))
    }

    @Test func requestsAgainAfterVersionBump() {
        #expect(ReviewPrompter.shouldRequest(lastPromptedVersion: "1.0", currentVersion: "1.1"))
    }

    @Test @MainActor func requestIfNeededStampsVersionAndFiresOnce() {
        let suiteName = "review-prompter-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var fireCount = 0
        ReviewPrompter.requestIfNeeded(defaults: defaults) { fireCount += 1 }
        ReviewPrompter.requestIfNeeded(defaults: defaults) { fireCount += 1 }

        #expect(fireCount == 1)
        #expect(defaults.string(forKey: ReviewPrompter.defaultsKey) != nil)
    }
}
