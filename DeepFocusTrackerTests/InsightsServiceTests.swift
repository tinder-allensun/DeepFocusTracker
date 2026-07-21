import Testing
import Foundation
@testable import DeepFocusCore

/// `InsightsService.compute` is the dashboard's brain — today/window totals, the
/// 14-day trend, the streak, and the by-app / by-label rollups. `now` and
/// `calendar` are injected, so every case here is deterministic (fixed UTC dates).
struct InsightsServiceTests {

    private let now = utcDate(2026, 1, 15, hour: 10)
    private let cal = Calendar.testUTC

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utcDate(y, m, d, hour: 0) }

    @Test func todayReflectsTodaysRollupOnly() {
        let days = [
            DayStat(day: day(2026, 1, 15), activeSeconds: 3600, awaySeconds: 300, blockCount: 2),
            DayStat(day: day(2026, 1, 14), activeSeconds: 1800, awaySeconds: 0, blockCount: 1),
        ]
        let insights = InsightsService.compute(days: days, appDays: [], sessions: [], now: now, calendar: cal)
        #expect(insights.todayActive == 3600)
        #expect(insights.todayBlocks == 2)
    }

    @Test func windowSumsInsideRangeAndExcludesOutside() {
        let days = [
            DayStat(day: day(2026, 1, 15), activeSeconds: 1000, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 10), activeSeconds: 2000, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 2), activeSeconds: 500, awaySeconds: 0, blockCount: 1),  // window start (inclusive)
            DayStat(day: day(2026, 1, 1), activeSeconds: 9999, awaySeconds: 0, blockCount: 5), // outside the 14-day window
        ]
        let insights = InsightsService.compute(days: days, appDays: [], sessions: [], now: now, calendar: cal)
        #expect(insights.windowActive == 3500)  // 1000 + 2000 + 500
        #expect(insights.windowBlocks == 3)
    }

    @Test func dailyIsAFullWindowOldestToNewestWithGapsAsZero() {
        let days = [
            DayStat(day: day(2026, 1, 15), activeSeconds: 1000, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 13), activeSeconds: 2000, awaySeconds: 0, blockCount: 1),
        ]
        let insights = InsightsService.compute(days: days, appDays: [], sessions: [], now: now, calendar: cal, trailingDays: 14)
        #expect(insights.daily.count == 14)
        #expect(insights.daily.first?.date == day(2026, 1, 2))   // oldest
        #expect(insights.daily.last?.date == day(2026, 1, 15))   // newest = today
        #expect(insights.daily.last?.seconds == 1000)
        #expect(insights.daily.first { $0.date == day(2026, 1, 13) }?.seconds == 2000)
        #expect(insights.daily.first { $0.date == day(2026, 1, 14) }?.seconds == 0) // a day with no data
    }

    @Test func streakCountsConsecutiveDaysEndingToday() {
        let days = [
            DayStat(day: day(2026, 1, 15), activeSeconds: 60, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 14), activeSeconds: 60, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 13), activeSeconds: 60, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 11), activeSeconds: 60, awaySeconds: 0, blockCount: 1), // gap at the 12th
        ]
        let insights = InsightsService.compute(days: days, appDays: [], sessions: [], now: now, calendar: cal)
        #expect(insights.streakDays == 3)
    }

    @Test func streakCountsFromYesterdayWhenTodayIsEmpty() {
        let days = [
            DayStat(day: day(2026, 1, 14), activeSeconds: 60, awaySeconds: 0, blockCount: 1),
            DayStat(day: day(2026, 1, 13), activeSeconds: 60, awaySeconds: 0, blockCount: 1),
        ]  // today (the 15th) has no block yet
        let insights = InsightsService.compute(days: days, appDays: [], sessions: [], now: now, calendar: cal)
        #expect(insights.streakDays == 2)
    }

    @Test func streakIsZeroWhenNeitherTodayNorYesterdayHasABlock() {
        let days = [DayStat(day: day(2026, 1, 13), activeSeconds: 60, awaySeconds: 0, blockCount: 1)]
        let insights = InsightsService.compute(days: days, appDays: [], sessions: [], now: now, calendar: cal)
        #expect(insights.streakDays == 0)
    }

    @Test func byAppSumsAcrossDaysSortsDescendingAndCapsAtEight() {
        var appDays: [AppDayStat] = []
        for i in 1...9 {  // 9 distinct apps: 900, 800, ... 100 seconds
            appDays.append(AppDayStat(day: day(2026, 1, 15), bundleID: "com.app\(i)", appName: "App\(i)", seconds: TimeInterval(1000 - i * 100)))
        }
        // Same bundle on a second day must fold into app1's total.
        appDays.append(AppDayStat(day: day(2026, 1, 14), bundleID: "com.app1", appName: "App1", seconds: 5000))

        let insights = InsightsService.compute(days: [], appDays: appDays, sessions: [], now: now, calendar: cal)
        #expect(insights.byApp.count == 8)                       // capped
        #expect(insights.byApp.first?.bundleID == "com.app1")    // 900 + 5000
        #expect(insights.byApp.first?.seconds == 5900)
        #expect(!insights.byApp.contains { $0.bundleID == "com.app9" })  // smallest dropped
    }

    @Test func byLabelRollsUpWindowedSessions() {
        let sessions = [
            SessionRecord(start: utcDate(2026, 1, 15, hour: 9), end: utcDate(2026, 1, 15, hour: 10), label: "Coding", activeSeconds: 3000, awaySeconds: 0),
            SessionRecord(start: utcDate(2026, 1, 14, hour: 9), end: utcDate(2026, 1, 14, hour: 10), label: "Coding", activeSeconds: 1000, awaySeconds: 0),
            SessionRecord(start: utcDate(2026, 1, 13, hour: 9), end: utcDate(2026, 1, 13, hour: 10), label: "Writing", activeSeconds: 2000, awaySeconds: 0),
            SessionRecord(start: utcDate(2026, 1, 1, hour: 9), end: utcDate(2026, 1, 1, hour: 10), label: "Coding", activeSeconds: 9999, awaySeconds: 0), // outside window
        ]
        let insights = InsightsService.compute(days: [], appDays: [], sessions: sessions, now: now, calendar: cal)
        #expect(insights.byLabel.count == 2)
        #expect(insights.byLabel.first?.label == "Coding")
        #expect(insights.byLabel.first?.seconds == 4000)
        #expect(insights.byLabel.first?.blocks == 2)
        let writing = insights.byLabel.first { $0.label == "Writing" }
        #expect(writing?.seconds == 2000)
        #expect(writing?.blocks == 1)
    }

    @Test func emptyInputGivesZeroedInsightsWithAFullZeroedTrend() {
        let insights = InsightsService.compute(days: [], appDays: [], sessions: [], now: now, calendar: cal)
        #expect(insights.todayActive == 0)
        #expect(insights.todayBlocks == 0)
        #expect(insights.streakDays == 0)
        #expect(insights.windowActive == 0)
        #expect(insights.byApp.isEmpty)
        #expect(insights.byLabel.isEmpty)
        #expect(insights.daily.count == 14)
        #expect(insights.daily.allSatisfy { $0.seconds == 0 })
    }
}
