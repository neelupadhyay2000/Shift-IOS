import Foundation
import Testing
import Models

/// Tests for ``WatchContext`` and ``WatchCommand`` dictionary round-trip encoding.
///
/// These shared types bridge Codable structs to the `[String: Any]` dictionaries
/// required by WCSession. Every field must survive a toDictionary → init(dictionary:) cycle.
struct WatchContextTests {

    // MARK: - WatchContext Round-Trip

    @Test func fullContextRoundTripsViaDictionary() {
        let now = Date.now
        let context = WatchContext(
            eventID: UUID(),
            eventTitle: "Smith Wedding",
            activeBlockTitle: "Ceremony",
            activeBlockEndTime: now.addingTimeInterval(1800),
            nextBlockTitle: "Cocktail Hour",
            nextBlockStartTime: now.addingTimeInterval(1800),
            sunsetTime: now.addingTimeInterval(7200),
            isLive: true
        )

        let dict = context.toDictionary()
        let decoded = WatchContext(dictionary: dict)

        #expect(decoded != nil)
        #expect(decoded?.eventID == context.eventID)
        #expect(decoded?.eventTitle == "Smith Wedding")
        #expect(decoded?.activeBlockTitle == "Ceremony")
        #expect(decoded?.nextBlockTitle == "Cocktail Hour")
        #expect(decoded?.isLive == true)

        // TimeInterval round-trip loses sub-second precision — compare to 1s tolerance.
        let endDelta = abs(decoded!.activeBlockEndTime.timeIntervalSince(context.activeBlockEndTime))
        #expect(endDelta < 1)

        let nextDelta = abs(decoded!.nextBlockStartTime!.timeIntervalSince(context.nextBlockStartTime!))
        #expect(nextDelta < 1)

        let sunsetDelta = abs(decoded!.sunsetTime!.timeIntervalSince(context.sunsetTime!))
        #expect(sunsetDelta < 1)
    }

    @Test func contextWithNilOptionalsRoundTrips() {
        let context = WatchContext(
            eventID: UUID(),
            eventTitle: "Gala",
            activeBlockTitle: "Setup",
            activeBlockEndTime: .now.addingTimeInterval(600),
            nextBlockTitle: nil,
            nextBlockStartTime: nil,
            sunsetTime: nil,
            isLive: false
        )

        let dict = context.toDictionary()
        let decoded = WatchContext(dictionary: dict)

        #expect(decoded != nil)
        #expect(decoded?.eventTitle == "Gala")
        #expect(decoded?.nextBlockTitle == nil)
        #expect(decoded?.nextBlockStartTime == nil)
        #expect(decoded?.sunsetTime == nil)
        #expect(decoded?.isLive == false)
    }

    @Test func contextFromInvalidDictionaryReturnsNil() {
        let invalidDict: [String: Any] = ["foo": "bar"]
        #expect(WatchContext(dictionary: invalidDict) == nil)
    }

    @Test func contextFromPartialDictionaryReturnsNil() {
        // Missing activeBlockEndTime and eventID
        let dict: [String: Any] = [
            "eventTitle": "Test",
            "activeBlockTitle": "Block",
            "isLive": true,
        ]
        #expect(WatchContext(dictionary: dict) == nil)
    }

    @Test func contextDictionaryOmitsNilOptionals() {
        let context = WatchContext(
            eventID: UUID(),
            eventTitle: "E",
            activeBlockTitle: "B",
            activeBlockEndTime: .now,
            isLive: true
        )

        let dict = context.toDictionary()
        #expect(dict["nextBlockTitle"] == nil)
        #expect(dict["nextBlockStartTime"] == nil)
        #expect(dict["sunsetTime"] == nil)
    }

    // MARK: - WatchCommand Round-Trip

    @Test func shiftCommandRoundTrips() {
        let command = WatchCommand(action: .shift, deltaMinutes: 5)
        let dict = command.toDictionary()
        let decoded = WatchCommand(dictionary: dict)

        #expect(decoded != nil)
        #expect(decoded?.action == .shift)
        #expect(decoded?.deltaMinutes == 5)
    }

    @Test func completeBlockCommandRoundTrips() {
        let command = WatchCommand(action: .completeBlock)
        let dict = command.toDictionary()
        let decoded = WatchCommand(dictionary: dict)

        #expect(decoded != nil)
        #expect(decoded?.action == .completeBlock)
        #expect(decoded?.deltaMinutes == nil)
    }

    @Test func commandFromInvalidDictionaryReturnsNil() {
        #expect(WatchCommand(dictionary: ["command": "unknown_action"]) == nil)
        #expect(WatchCommand(dictionary: ["foo": "bar"]) == nil)
        #expect(WatchCommand(dictionary: [:]) == nil)
    }

    @Test func commandDictionaryOmitsNilMinutes() {
        let command = WatchCommand(action: .completeBlock)
        let dict = command.toDictionary()
        #expect(dict["minutes"] == nil)
    }

    // MARK: - Codable Round-Trip

    @Test func watchContextCodableRoundTrip() throws {
        let context = WatchContext(
            eventID: UUID(),
            eventTitle: "Event",
            activeBlockTitle: "Block",
            activeBlockEndTime: .now,
            nextBlockTitle: "Next",
            nextBlockStartTime: .now.addingTimeInterval(60),
            sunsetTime: .now.addingTimeInterval(3600),
            isLive: true
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(WatchContext.self, from: data)
        #expect(decoded == context)
    }

    @Test func watchCommandCodableRoundTrip() throws {
        let command = WatchCommand(action: .shift, deltaMinutes: 15)
        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: data)
        #expect(decoded == command)
    }
}
