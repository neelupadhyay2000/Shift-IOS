import Foundation
import Testing

@testable import shiftTimeline

/// Tests the global "Notify me when shift exceeds…" Settings threshold gating
/// logic in `VendorShiftLocalNotifier.shouldPostVisibleNotification`.
///
/// The global threshold acts as an additional FLOOR on top of each vendor's
/// per-vendor `notificationThreshold`. Visible pushes fire only when the
/// shift delta meets or exceeds whichever threshold is larger.
@Suite("Global Notification Threshold")
struct GlobalNotificationThresholdTests {

    // MARK: - Both thresholds satisfied

    @Test func postsWhenDeltaExceedsBothThresholds() {
        let result = VendorShiftLocalNotifier.shouldPostVisibleNotification(
            delta: 900, // 15 min
            vendorThresholdSeconds: 600, // 10 min
            globalThresholdSeconds: 600  // 10 min
        )
        #expect(result == true)
    }

    // MARK: - Vendor threshold met, global not

    @Test func suppressesWhenGlobalThresholdHigherThanDelta() {
        // Vendor would want notification (delta > vendor threshold) but the
        // planner's global setting is stricter — silent.
        let result = VendorShiftLocalNotifier.shouldPostVisibleNotification(
            delta: 600, // 10 min
            vendorThresholdSeconds: 300, // 5 min
            globalThresholdSeconds: 1200 // 20 min
        )
        #expect(result == false)
    }

    // MARK: - Global threshold met, vendor not

    @Test func suppressesWhenVendorThresholdHigherThanDelta() {
        // Vendor's per-vendor preference is stricter than the global floor.
        let result = VendorShiftLocalNotifier.shouldPostVisibleNotification(
            delta: 700, // ~11.5 min
            vendorThresholdSeconds: 1800, // 30 min
            globalThresholdSeconds: 600   // 10 min
        )
        #expect(result == false)
    }

    // MARK: - Negative delta (early shift)

    @Test func usesAbsoluteValueForNegativeDelta() {
        let result = VendorShiftLocalNotifier.shouldPostVisibleNotification(
            delta: -900, // running 15 min early
            vendorThresholdSeconds: 600,
            globalThresholdSeconds: 600
        )
        #expect(result == true)
    }

    // MARK: - Exact threshold

    @Test func postsWhenDeltaExactlyEqualsEffectiveThreshold() {
        let result = VendorShiftLocalNotifier.shouldPostVisibleNotification(
            delta: 600,
            vendorThresholdSeconds: 600,
            globalThresholdSeconds: 600
        )
        #expect(result == true)
    }

    // MARK: - Zero delta

    @Test func suppressesWhenDeltaIsZero() {
        let result = VendorShiftLocalNotifier.shouldPostVisibleNotification(
            delta: 0,
            vendorThresholdSeconds: 600,
            globalThresholdSeconds: 600
        )
        #expect(result == false)
    }
}
