import Testing
import Foundation
@testable import DeepFocusCore

/// `InsightsService.dayReview` backs the "Today" review screen: it sums a single
/// day's completed blocks (active / away / blocks / switches) and folds the day's
/// per-app rollups into a descending breakdown. `now` / `calendar` are injected, so
/// every case is deterministic (fixed UTC dates) and the day-scoping is testable.
struct DayReviewTests {

    private let now = utcDate(2026, 1, 15, hour: 10)
    private let cal = Calendar.testUTC

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utcDate(y, m, d, hour: 0) }

    /// A completed block on the given day (defaults to today, the 15th).
    private func block(
        hour: Int,
        label: String = "Work",
        active: TimeInterval,
        away: TimeInterval = 0,
        switches: Int = 0,
        on date: (Int, Int, Int) = (2026, 1, 15)
    ) -> SessionRecord {
        SessionRecord(
            start: utcDate(date.0, date.1, date.2, hour: hour),
            end: utcDate(date.0, date.1, date.2, hour: hour + 1),
            label: label,
            activeSeconds: active,
            awaySeconds: away,
            switchCount: switches
        )
    }

    @Test func totalsSumTodaysBlocksAndExcludeOtherDays() {
        let sessions = [
            block(hour: 9, active: 3000, away: 120, switches: 10),
            block(hour: 11, active: 1500, away: 60, switches: 8),
            block(hour: 9, active: 9999, away: 999, switches: 99, on: (2026, 1, 14)), // yesterday — excluded
        ]
        let review = InsightsService.dayReview(sessions: sessions, appDays: [], now: now, calendar: cal)
        #expect(review.activeSeconds == 4500)
        #expect(review.awaySeconds == 180)
        #expect(review.blockCount == 2)
        #expect(review.switchCount == 18)
    }

    @Test func perAppFoldsTodaysRollupsSortedDescendingAndExcludesOtherDays() {
        let appDays = [
            AppDayStat(day: day(2026, 1, 15), bundleID: "com.a", appName: "A", seconds: 600),
            AppDayStat(day: day(2026, 1, 15), bundleID: "com.b", appName: "B", seconds: 1800),
            AppDayStat(day: day(2026, 1, 15), bundleID: "com.c", appName: "C", seconds: 300),
            AppDayStat(day: day(2026, 1, 14), bundleID: "com.d", appName: "D", seconds: 9999), // other day — excluded
        ]
        let review = InsightsService.dayReview(sessions: [], appDays: appDays, now: now, calendar: cal)
        #expect(review.byApp.map(\.bundleID) == ["com.b", "com.a", "com.c"])
        #expect(review.byApp.first?.seconds == 1800)
        #expect(!review.byApp.contains { $0.bundleID == "com.d" })
    }

    @Test func emptyInputGivesAZeroedReview() {
        let review = InsightsService.dayReview(sessions: [], appDays: [], now: now, calendar: cal)
        #expect(review.activeSeconds == 0)
        #expect(review.awaySeconds == 0)
        #expect(review.blockCount == 0)
        #expect(review.switchCount == 0)
        #expect(review.byApp.isEmpty)
    }

    @Test func aDayWithOnlyOtherDaysDataReviewsAsEmpty() {
        let sessions = [block(hour: 9, active: 3000, switches: 5, on: (2026, 1, 14))]
        let appDays = [AppDayStat(day: day(2026, 1, 14), bundleID: "com.a", appName: "A", seconds: 3000)]
        let review = InsightsService.dayReview(sessions: sessions, appDays: appDays, now: now, calendar: cal)
        #expect(review.blockCount == 0)
        #expect(review.activeSeconds == 0)
        #expect(review.byApp.isEmpty)
    }

    // MARK: Off-focus gaps

    @Test func gapAppearsBetweenConsecutiveBlocksWithItsDurationAndBounds() {
        // 09:00–10:00, then 11:00–12:00 → a 1h off-focus gap in between.
        let review = InsightsService.dayReview(
            sessions: [block(hour: 9, active: 3600), block(hour: 11, active: 3600)],
            appDays: [], now: now, calendar: cal
        )
        #expect(review.gaps.count == 1)
        let gap = review.gaps.first
        #expect(gap?.precedingIndex == 0)
        #expect(gap?.duration == 3600)
        #expect(gap?.start == utcDate(2026, 1, 15, hour: 10))
        #expect(gap?.end == utcDate(2026, 1, 15, hour: 11))
    }

    @Test func aSingleBlockHasNoGaps() {
        let review = InsightsService.dayReview(
            sessions: [block(hour: 9, active: 3600)], appDays: [], now: now, calendar: cal
        )
        #expect(review.gaps.isEmpty)
    }

    @Test func subMinuteGapsAreOmittedAsNoise() {
        // 09:00–10:00, then a block starting 30s later — below the 60s floor.
        let a = SessionRecord(
            start: utcDate(2026, 1, 15, hour: 9), end: utcDate(2026, 1, 15, hour: 10),
            label: "A", activeSeconds: 3600, awaySeconds: 0
        )
        let b = SessionRecord(
            start: utcDate(2026, 1, 15, hour: 10).addingTimeInterval(30),
            end: utcDate(2026, 1, 15, hour: 11),
            label: "B", activeSeconds: 3000, awaySeconds: 0
        )
        let review = InsightsService.dayReview(sessions: [a, b], appDays: [], now: now, calendar: cal)
        #expect(review.gaps.isEmpty)
    }

    @Test func multipleGapsCarryTheirPrecedingBlockIndexInChronologicalOrder() {
        // Deliberately unsorted input: dayReview must sort before pairing, so the
        // gaps' precedingIndex matches the view's chronological @Query order.
        let sessions = [
            block(hour: 14, active: 3600), // 14:00–15:00
            block(hour: 9, active: 3600),  // 09:00–10:00
            block(hour: 11, active: 3600), // 11:00–12:00
        ]
        let review = InsightsService.dayReview(sessions: sessions, appDays: [], now: now, calendar: cal)
        #expect(review.gaps.map(\.precedingIndex) == [0, 1])
        #expect(review.gaps.map(\.duration) == [3600, 7200]) // 10→11 = 1h; 12→14 = 2h
    }

    @Test func gapsNeverPairAcrossDays() {
        // A block today and one yesterday must not form a cross-day gap.
        let sessions = [
            block(hour: 9, active: 3600),
            block(hour: 15, active: 3600, on: (2026, 1, 14)),
        ]
        let review = InsightsService.dayReview(sessions: sessions, appDays: [], now: now, calendar: cal)
        #expect(review.blockCount == 1)
        #expect(review.gaps.isEmpty)
    }
}
