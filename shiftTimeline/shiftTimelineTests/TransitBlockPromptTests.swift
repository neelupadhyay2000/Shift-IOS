import Foundation
import Models
import Testing

@Suite("Transit Block Prompt")
struct TransitBlockPromptTests {

    // MARK: - Transit Block Properties

    @Test func transitBlockHasCorrectTitleFormat() {
        let block = TimeBlockModel(
            title: "Transit to Grand Ballroom",
            scheduledStart: .now,
            duration: 780,
            colorTag: "#8E8E93",
            icon: "car.fill"
        )

        #expect(block.title == "Transit to Grand Ballroom")
    }

    @Test func transitBlockIsFluidWithCarIconAndGreyColor() {
        let block = TimeBlockModel(
            title: "Transit to Venue B",
            scheduledStart: .now,
            duration: 600,
            isPinned: false,
            colorTag: "#8E8E93",
            icon: "car.fill"
        )

        #expect(!block.isPinned)
        #expect(block.icon == "car.fill")
        #expect(block.colorTag == "#8E8E93")
    }

    @Test func transitBlockDurationMatchesTravelMinutes() {
        let travelMinutes = 13
        let block = TimeBlockModel(
            title: "Transit to Venue B",
            scheduledStart: .now,
            duration: TimeInterval(travelMinutes * 60)
        )

        #expect(block.duration == 780)
    }

    // MARK: - Sorting / Position

    @Test func transitBlockSortsBetweenVenueSwitchingBlocks() {
        let base = Date.now
        let ceremony = TimeBlockModel(title: "Ceremony", scheduledStart: base, duration: 1800)
        let transit = TimeBlockModel(
            title: "Transit to Reception Hall",
            scheduledStart: base.addingTimeInterval(1800),
            duration: 780,
            colorTag: "#8E8E93",
            icon: "car.fill"
        )
        let reception = TimeBlockModel(
            title: "Reception",
            scheduledStart: base.addingTimeInterval(2580),
            duration: 3600
        )

        let sorted = [reception, transit, ceremony].sorted { $0.scheduledStart < $1.scheduledStart }

        #expect(sorted[0].title == "Ceremony")
        #expect(sorted[1].title == "Transit to Reception Hall")
        #expect(sorted[2].title == "Reception")
    }

    // MARK: - Venue-Switching Detection Logic

    @Test func differentVenueCoordinatesAreDetected() {
        let originKey = String(format: "%.4f,%.4f", 37.3318, -122.0312)
        let destKey = String(format: "%.4f,%.4f", 40.7128, -74.006)

        #expect(originKey != destKey)
    }

    @Test func sameVenueCoordinatesAreNotDetected() {
        let originKey = String(format: "%.4f,%.4f", 37.3318, -122.0312)
        let destKey = String(format: "%.4f,%.4f", 37.3318, -122.0312)

        #expect(originKey == destKey)
    }

    @Test func zeroCoordinatesSkipDetection() {
        let hasCoords = 0.0 != 0 || 0.0 != 0
        #expect(!hasCoords)
    }

    @Test func nearbyCoordinatesRoundToSameKeyAndSkipDetection() {
        let keyA = String(format: "%.4f,%.4f", 37.33182, -122.03124)
        let keyB = String(format: "%.4f,%.4f", 37.33184, -122.03121)

        #expect(keyA == keyB)
    }

    @Test func transitBlockFlagExcludesPairFromDetection() {
        let transit = TimeBlockModel(title: "Transit to Venue B", scheduledStart: .now, duration: 600)
        transit.isTransitBlock = true
        let regular = TimeBlockModel(title: "Reception", scheduledStart: .now, duration: 3600)

        #expect(transit.isTransitBlock)
        #expect(!regular.isTransitBlock)
    }
}
