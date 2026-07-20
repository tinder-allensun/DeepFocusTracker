import Testing
import Foundation
@testable import DeepFocusTracker

/// `UsageAggregator` is the pure per-app rollup at the heart of both the live
/// popover and the session-detail view. These pin its grouping, ordering, and the
/// "active excludes away" rule that the per-app percentages depend on.
struct UsageAggregatorTests {

    private func span(_ bundle: String, _ name: String, _ duration: TimeInterval) -> AppSpan {
        AppSpan(bundleID: bundle, appName: name, start: utcDate(2026, 1, 1), duration: duration)
    }

    @Test func emptyInputHasNoActiveTimeButKeepsAway() {
        let summary = UsageAggregator.summarize(spans: [], awaySeconds: 120, switchCount: 0)
        #expect(summary.perApp.isEmpty)
        #expect(summary.activeSeconds == 0)
        #expect(summary.awaySeconds == 120)
        // Guard the divide-by-zero path in `fraction(of:)`.
        #expect(summary.fraction(of: AppUsage(bundleID: "x", appName: "X", seconds: 10)) == 0)
    }

    @Test func sumsMultipleSpansOfTheSameApp() {
        let summary = UsageAggregator.summarize(
            spans: [span("com.a", "A", 100), span("com.a", "A", 50), span("com.b", "B", 30)],
            awaySeconds: 0, switchCount: 2
        )
        #expect(summary.perApp.count == 2)
        #expect(summary.perApp.first { $0.bundleID == "com.a" }?.seconds == 150)
        #expect(summary.perApp.first { $0.bundleID == "com.b" }?.seconds == 30)
    }

    @Test func sortsAppsByTimeDescending() {
        let summary = UsageAggregator.summarize(
            spans: [span("com.small", "S", 30), span("com.big", "B", 300), span("com.mid", "M", 90)],
            awaySeconds: 0, switchCount: 0
        )
        #expect(summary.perApp.map(\.bundleID) == ["com.big", "com.mid", "com.small"])
    }

    @Test func activeSecondsIsTheSumOfAppsAndExcludesAway() {
        let summary = UsageAggregator.summarize(
            spans: [span("com.a", "A", 200), span("com.b", "B", 100)],
            awaySeconds: 500, switchCount: 1
        )
        #expect(summary.activeSeconds == 300)
        #expect(summary.awaySeconds == 500)
        #expect(summary.switchCount == 1)
    }

    @Test func fractionIsShareOfActiveTimeNotTotalTime() {
        let summary = UsageAggregator.summarize(
            spans: [span("com.a", "A", 300), span("com.b", "B", 100)],
            awaySeconds: 9_999, switchCount: 0
        )
        let a = try! #require(summary.perApp.first { $0.bundleID == "com.a" })
        // 300 / (300 + 100) — the large away time must not dilute the fraction.
        #expect(abs(summary.fraction(of: a) - 0.75) < 1e-9)
    }
}
