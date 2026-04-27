//
//  DurationFormatterTests.swift
//  shiftTimelineTests
//
//  Verifies that minute-based durations roll up to hours at the 60-minute
//  boundary so users never see misleading values like "90 min".
//

import Foundation
import Testing
@testable import shiftTimeline

@Suite("DurationFormatter")
struct DurationFormatterTests {

    // MARK: - Unsigned

    @Test func belowOneHourReturnsMinutes() {
        #expect(DurationFormatter.compact(minutes: 0) == "0 min")
        #expect(DurationFormatter.compact(minutes: 1) == "1 min")
        #expect(DurationFormatter.compact(minutes: 45) == "45 min")
        #expect(DurationFormatter.compact(minutes: 59) == "59 min")
    }

    @Test func exactlyOneHourCollapsesToHours() {
        #expect(DurationFormatter.compact(minutes: 60) == "1h")
        #expect(DurationFormatter.compact(minutes: 120) == "2h")
    }

    @Test func mixedHoursAndMinutes() {
        #expect(DurationFormatter.compact(minutes: 61) == "1h 1m")
        #expect(DurationFormatter.compact(minutes: 90) == "1h 30m")
        #expect(DurationFormatter.compact(minutes: 125) == "2h 5m")
    }

    // MARK: - Signed

    @Test func signedZero() {
        #expect(DurationFormatter.compact(minutes: 0, signed: true) == "0 min")
    }

    @Test func signedPositive() {
        #expect(DurationFormatter.compact(minutes: 5, signed: true) == "+5 min")
        #expect(DurationFormatter.compact(minutes: 90, signed: true) == "+1h 30m")
    }

    @Test func signedNegative() {
        #expect(DurationFormatter.compact(minutes: -10, signed: true) == "-10 min")
        #expect(DurationFormatter.compact(minutes: -75, signed: true) == "-1h 15m")
        #expect(DurationFormatter.compact(minutes: -120, signed: true) == "-2h")
    }

    // MARK: - TimeInterval overload

    @Test func secondsOverloadFloorsToWholeMinutes() {
        #expect(DurationFormatter.compact(seconds: 0) == "0 min")
        #expect(DurationFormatter.compact(seconds: 59) == "0 min")
        #expect(DurationFormatter.compact(seconds: 60) == "1 min")
        #expect(DurationFormatter.compact(seconds: 3_600) == "1h")
        #expect(DurationFormatter.compact(seconds: 5_400) == "1h 30m")
    }

    @Test func secondsOverloadHandlesSignedNegatives() {
        // TimeInterval can be negative (e.g. event running early).
        #expect(DurationFormatter.compact(seconds: -3_600, signed: true) == "-1h")
        #expect(DurationFormatter.compact(seconds: -1_500, signed: true) == "-25 min")
    }
}
