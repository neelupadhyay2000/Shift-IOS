import Foundation
import Testing
import TestSupport

/// Verifies `TestFixture` name serialisation / deserialisation and `TestClock` behaviour.
/// These tests are pure — no SwiftData, no network, no I/O, no `@MainActor`.
@Suite("TestFixture registry")
struct TestFixtureRegistryTests {

    // MARK: - Simple-case roundtrip

    @Test("Non-parameterised fixtures survive a serialisedName → named() roundtrip")
    func simpleCaseRoundtrip() {
        let cases: [TestFixture] = [
            .singleEventFiveBlocks,
            .weddingTemplateApplied,
            .multiTrackConference,
            .eventWithRainForecastedBlock,
            .eventWithSunsetBlocks,
        ]
        for fixture in cases {
            #expect(
                TestFixture.named(fixture.serialisedName) == fixture,
                "Roundtrip failed for '\(fixture.serialisedName)'"
            )
        }
    }

    // MARK: - Parameterised-case roundtrip

    @Test("eventWithVendors roundtrips its count")
    func eventWithVendorsRoundtrip() {
        #expect(TestFixture.named("eventWithVendors_0")  == .eventWithVendors(count: 0))
        #expect(TestFixture.named("eventWithVendors_3")  == .eventWithVendors(count: 3))
        #expect(TestFixture.named("eventWithVendors_10") == .eventWithVendors(count: 10))
    }

    @Test("liveEventInProgress roundtrips its blockIndex")
    func liveEventInProgressRoundtrip() {
        #expect(TestFixture.named("liveEventInProgress_0") == .liveEventInProgress(blockIndex: 0))
        #expect(TestFixture.named("liveEventInProgress_2") == .liveEventInProgress(blockIndex: 2))
        #expect(TestFixture.named("liveEventInProgress_4") == .liveEventInProgress(blockIndex: 4))
    }

    @Test("Parameterised serialisedNames roundtrip with their associated values")
    func parameterisedSerialisedNameRoundtrip() {
        let vendors3 = TestFixture.eventWithVendors(count: 3)
        let live2    = TestFixture.liveEventInProgress(blockIndex: 2)
        #expect(TestFixture.named(vendors3.serialisedName) == vendors3)
        #expect(TestFixture.named(live2.serialisedName)    == live2)
    }

    // MARK: - Invalid tokens

    @Test("Unknown or malformed tokens return nil")
    func unknownNamesReturnNil() {
        #expect(TestFixture.named("")                         == nil)
        #expect(TestFixture.named("unknown")                  == nil)
        #expect(TestFixture.named("eventWithVendors_")        == nil) // missing int
        #expect(TestFixture.named("eventWithVendors_-1")      == nil) // negative
        #expect(TestFixture.named("liveEventInProgress_")     == nil) // missing int
        #expect(TestFixture.named("liveEventInProgress_-2")   == nil) // negative
    }

    // MARK: - serialisedName uniqueness

    @Test("All non-parameterised serialisedNames are distinct")
    func serialisedNamesAreUnique() {
        let names = [
            TestFixture.singleEventFiveBlocks.serialisedName,
            TestFixture.weddingTemplateApplied.serialisedName,
            TestFixture.multiTrackConference.serialisedName,
            TestFixture.eventWithRainForecastedBlock.serialisedName,
            TestFixture.eventWithSunsetBlocks.serialisedName,
        ]
        #expect(Set(names).count == names.count)
    }

    // MARK: - TestClock

    @Test("TestClock.reference is stable across accesses")
    func referenceClockIsStable() {
        #expect(TestClock.reference.now == TestClock.reference.now)
    }

    @Test("TestClock(now:) round-trips the exact date")
    func clockRoundtripsDate() {
        let target = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(now: target)
        #expect(clock.now == target)
    }

    @Test("TestClock.reference is after the Unix epoch")
    func referenceClockIsAfterEpoch() {
        #expect(TestClock.reference.now > Date(timeIntervalSince1970: 0))
    }

    @Test("Two TestClock instances with the same date are equal via their now property")
    func twoClocksSameDateProduceSameNow() {
        let date = TestClock.reference.now
        let a = TestClock(now: date)
        let b = TestClock(now: date)
        #expect(a.now == b.now)
    }
}
