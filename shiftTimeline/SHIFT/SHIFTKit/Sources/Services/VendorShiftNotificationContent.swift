import Foundation
import Models

/// Pure-logic notification content builder for vendor shift alerts.
///
/// Lives in SHIFTKit so it's testable from the test target. The app-layer
/// `VendorShiftLocalNotifier` calls these helpers to build the
/// `UNMutableNotificationContent` body.
public enum VendorShiftNotificationContent {

    /// Key used in notification `userInfo` to pass the event ID for deep-linking.
    public static let eventIDKey = "com.shift.eventID"

    /// Builds the notification body string, e.g.:
    /// "Timeline shifted +15 min. Your next block 'Family Photos' now starts at 3:15 PM."
    public static func body(
        delta: TimeInterval,
        vendor: VendorModel
    ) -> String {
        let deltaMinutes = Int(delta / 60)
        let sign = deltaMinutes >= 0 ? "+" : ""
        let shiftText = "Timeline shifted \(sign)\(deltaMinutes) min."

        guard let nextBlock = nextUpcomingBlock(for: vendor) else {
            return shiftText
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let timeString = formatter.string(from: nextBlock.scheduledStart)

        return "\(shiftText) Your next block '\(nextBlock.title)' now starts at \(timeString)."
    }

    /// Returns the vendor's next upcoming assigned block (sorted by `scheduledStart`),
    /// excluding completed blocks.
    public static func nextUpcomingBlock(for vendor: VendorModel) -> TimeBlockModel? {
        (vendor.assignedBlocks ?? [])
            .filter { $0.status != .completed }
            .sorted { $0.scheduledStart < $1.scheduledStart }
            .first
    }
}
