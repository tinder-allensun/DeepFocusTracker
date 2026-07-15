import Foundation

/// A contiguous span where one app was frontmost (in-memory; persisted as an
/// `AppInterval`). The `start` is kept so it can be written to the store.
struct AppSpan {
    let bundleID: String
    let appName: String
    let start: Date
    var duration: TimeInterval
}

/// Per-app rollup for a block.
struct AppUsage: Identifiable {
    let bundleID: String
    let appName: String
    let seconds: TimeInterval
    var id: String { bundleID }
}

/// The computed breakdown for a block — no focus/distraction judgment, just the
/// numbers the user reviews.
struct UsageSummary {
    /// Apps sorted by time spent, descending.
    let perApp: [AppUsage]
    /// Total time attributed to apps (excludes Away).
    let activeSeconds: TimeInterval
    /// Total idle / away time.
    let awaySeconds: TimeInterval
    /// Number of frontmost-app switches during the block.
    let switchCount: Int

    static let empty = UsageSummary(perApp: [], activeSeconds: 0, awaySeconds: 0, switchCount: 0)

    /// Fraction of active (non-away) time spent in the given app (0...1).
    func fraction(of usage: AppUsage) -> Double {
        activeSeconds > 0 ? usage.seconds / activeSeconds : 0
    }
}

/// Pure aggregation of raw spans into a per-app breakdown. UI-independent and
/// unit-testable; deliberately makes no judgment about which apps are "focus."
enum UsageAggregator {
    static func summarize(spans: [AppSpan], awaySeconds: TimeInterval, switchCount: Int) -> UsageSummary {
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        for span in spans {
            let running = totals[span.bundleID]?.seconds ?? 0
            totals[span.bundleID] = (span.appName, running + span.duration)
        }
        let perApp = totals
            .map { AppUsage(bundleID: $0.key, appName: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }
        let active = perApp.reduce(0) { $0 + $1.seconds }
        return UsageSummary(
            perApp: perApp,
            activeSeconds: active,
            awaySeconds: awaySeconds,
            switchCount: switchCount
        )
    }
}
