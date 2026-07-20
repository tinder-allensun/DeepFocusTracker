import Testing
import Foundation
@testable import DeepFocusTracker

/// `TimeFormat` is the formatting boundary (see ARCHITECTURE.md "Units, storage &
/// the formatting boundary"). These pin the exact strings each formatter emits at
/// the granularity edges, so a refactor can't silently change what the user reads.
struct TimeFormatTests {

    // MARK: clock (MM:SS / H:MM:SS) — the live, ticking timer

    @Test func clockFormatsUnderAnHourAsMinutesSeconds() {
        #expect(TimeFormat.clock(0) == "00:00")
        #expect(TimeFormat.clock(5) == "00:05")
        #expect(TimeFormat.clock(59) == "00:59")
        #expect(TimeFormat.clock(60) == "01:00")
        #expect(TimeFormat.clock(65) == "01:05")
        #expect(TimeFormat.clock(600) == "10:00")
    }

    @Test func clockAddsHoursPastAnHour() {
        #expect(TimeFormat.clock(3600) == "1:00:00")
        #expect(TimeFormat.clock(3661) == "1:01:01")
        #expect(TimeFormat.clock(36000) == "10:00:00")
    }

    @Test func clockRoundsToNearestSecondAndClampsNegatives() {
        #expect(TimeFormat.clock(65.4) == "01:05")
        #expect(TimeFormat.clock(65.6) == "01:06")
        // Negative (e.g. a mis-timed countdown) never renders as garbage.
        #expect(TimeFormat.clock(-10) == "00:00")
    }

    // MARK: compact (45s / 25m / 1h 20m) — self-labeling aggregate totals

    @Test func compactShowsSecondsUnderAMinute() {
        #expect(TimeFormat.compact(0) == "0s")
        #expect(TimeFormat.compact(1) == "1s")
        #expect(TimeFormat.compact(59) == "59s")
    }

    @Test func compactShowsWholeMinutesUpToAnHour() {
        #expect(TimeFormat.compact(60) == "1m")
        #expect(TimeFormat.compact(90) == "1m")   // truncates to whole minutes
        #expect(TimeFormat.compact(1500) == "25m")
        #expect(TimeFormat.compact(3540) == "59m")
    }

    @Test func compactShowsHoursAndMinutesPastAnHour() {
        #expect(TimeFormat.compact(3600) == "1h")           // exact hour: no "0m"
        #expect(TimeFormat.compact(3660) == "1h 1m")
        #expect(TimeFormat.compact(4800) == "1h 20m")
        #expect(TimeFormat.compact(36000) == "10h")
    }

    @Test func compactClampsNegatives() {
        #expect(TimeFormat.compact(-5) == "0s")
    }
}
