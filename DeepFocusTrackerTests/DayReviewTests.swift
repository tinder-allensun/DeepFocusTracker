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
}
