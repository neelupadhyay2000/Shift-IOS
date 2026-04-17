import Foundation
import Models
import Services
import Testing

@Suite("Vendor Shift Notification Body")
struct VendorShiftNotificationBodyTests {

    // MARK: - Body With Next Block

    @Test func bodyIncludesDeltaAndNextBlock() {
        let vendor = VendorModel(name: "DJ Mike", role: .dj)
        let block = TimeBlockModel(
            title: "Family Photos",
            scheduledStart: makeDate(hour: 15, minute: 15),
            duration: 3600,
            isPinned: false
        )
        block.status = .upcoming
        vendor.assignedBlocks = [block]

        let body = VendorShiftNotificationContent.body(
            delta: 900, // +15 min
            vendor: vendor
        )

        #expect(body.contains("+15 min"))
        #expect(body.contains("Family Photos"))
        // Time format varies by locale (e.g. "3:15 PM" vs "15:15").
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let expectedTime = formatter.string(from: makeDate(hour: 15, minute: 15))
        #expect(body.contains(expectedTime))
    }

    // MARK: - Negative Delta

    @Test func bodyShowsNegativeDelta() {
        let vendor = VendorModel(name: "DJ", role: .dj)
        let block = TimeBlockModel(
            title: "Set",
            scheduledStart: makeDate(hour: 14, minute: 0),
            duration: 3600,
            isPinned: false
        )
        block.status = .upcoming
        vendor.assignedBlocks = [block]

        let body = VendorShiftNotificationContent.body(
            delta: -600, // -10 min
            vendor: vendor
        )

        #expect(body.contains("-10 min"))
    }

    // MARK: - No Upcoming Blocks

    @Test func bodyWithoutBlocksShowsDeltaOnly() {
        let vendor = VendorModel(name: "Caterer", role: .caterer)
        vendor.assignedBlocks = []

        let body = VendorShiftNotificationContent.body(
            delta: 900,
            vendor: vendor
        )

        #expect(body.contains("+15 min"))
        #expect(!body.contains("Your next block"))
    }

    // MARK: - Completed Blocks Are Skipped

    @Test func completedBlocksExcludedFromBody() {
        let vendor = VendorModel(name: "Photographer", role: .photographer)

        let completed = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: makeDate(hour: 12, minute: 0),
            duration: 1800,
            isPinned: false
        )
        completed.status = .completed

        let upcoming = TimeBlockModel(
            title: "Reception",
            scheduledStart: makeDate(hour: 16, minute: 30),
            duration: 3600,
            isPinned: false
        )
        upcoming.status = .upcoming

        vendor.assignedBlocks = [completed, upcoming]

        let body = VendorShiftNotificationContent.body(
            delta: 600,
            vendor: vendor
        )

        #expect(body.contains("Reception"))
        #expect(!body.contains("Ceremony"))
    }

    // MARK: - Per-Vendor Personalisation

    @Test func differentVendorsGetDifferentBodies() {
        let dj = VendorModel(name: "DJ", role: .dj)
        let djBlock = TimeBlockModel(
            title: "DJ Set",
            scheduledStart: makeDate(hour: 20, minute: 0),
            duration: 7200,
            isPinned: false
        )
        djBlock.status = .upcoming
        dj.assignedBlocks = [djBlock]

        let caterer = VendorModel(name: "Caterer", role: .caterer)
        let catererBlock = TimeBlockModel(
            title: "Dinner Service",
            scheduledStart: makeDate(hour: 18, minute: 30),
            duration: 5400,
            isPinned: false
        )
        catererBlock.status = .upcoming
        caterer.assignedBlocks = [catererBlock]

        let djBody = VendorShiftNotificationContent.body(delta: 900, vendor: dj)
        let catererBody = VendorShiftNotificationContent.body(delta: 900, vendor: caterer)

        #expect(djBody.contains("DJ Set"))
        #expect(catererBody.contains("Dinner Service"))
        #expect(djBody != catererBody)
    }

    // MARK: - Deep-Link Key

    @Test func eventIDKeyIsStable() {
        #expect(VendorShiftNotificationContent.eventIDKey == "com.shift.eventID")
    }

    // MARK: - Helpers

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: .now
        )
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
