import Foundation

/// A completed focus block, as a plain value for aggregation.
struct SessionRecord {
    let start: Date
    let end: Date
    let label: String
    let activeSeconds: TimeInterval
    let awaySeconds: TimeInterval
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Active time on a single day (for the trend chart).
struct DayActive: Identifiable {
    let date: Date
    let seconds: TimeInterval
    var id: Date { date }
}

/// Active time rolled up by label.
struct LabelUsage: Identifiable {
    let label: String
    let seconds: TimeInterval
    let blocks: Int
    var id: String { label }
}

/// Everything the dashboard shows, computed from stored history.
struct Insights {
    let todayActive: TimeInterval
    let todayBlocks: Int
    let streakDays: Int
    let windowActive: TimeInterval
    let windowBlocks: Int
    let daily: [DayActive]      // oldest → newest, one entry per day in the window
    let byApp: [AppUsage]       // top apps by active time (window)
    let byLabel: [LabelUsage]   // labels by active time (window)

    static let empty = Insights(
        todayActive: 0, todayBlocks: 0, streakDays: 0,
        windowActive: 0, windowBlocks: 0, daily: [], byApp: [], byLabel: []
    )
}

/// Pure aggregation of stored history into dashboard figures. No side effects;
/// deterministic given its inputs (`now` / `calendar` are injected).
enum InsightsService {
    static func compute(
        sessions: [SessionRecord],
        appSpans: [AppSpan],
        now: Date = .now,
        calendar: Calendar = .current,
        trailingDays: Int = 14
    ) -> Insights {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(trailingDays - 1), to: today) ?? today

        // Today
        let todaySessions = sessions.filter { calendar.isDate($0.start, inSameDayAs: now) }
        let todayActive = todaySessions.reduce(0) { $0 + $1.activeSeconds }

        // Window
        let windowSessions = sessions.filter { $0.start >= windowStart }
        let windowActive = windowSessions.reduce(0) { $0 + $1.activeSeconds }

        // Daily buckets
        var buckets: [Date: TimeInterval] = [:]
        for session in windowSessions {
            buckets[calendar.startOfDay(for: session.start), default: 0] += session.activeSeconds
        }
        var daily: [DayActive] = []
        for offset in stride(from: trailingDays - 1, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            daily.append(DayActive(date: day, seconds: buckets[day] ?? 0))
        }

        // Current streak: consecutive days (ending today, or yesterday if today
        // is empty) that have at least one block.
        let daysWithBlocks = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        var streak = 0
        var cursor = daysWithBlocks.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while daysWithBlocks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        // Per-app: reuse the block-level aggregator over the window's spans.
        let windowSpans = appSpans.filter { $0.start >= windowStart }
        let byApp = Array(
            UsageAggregator.summarize(spans: windowSpans, awaySeconds: 0, switchCount: 0).perApp.prefix(8)
        )

        // Per-label
        var labelSeconds: [String: TimeInterval] = [:]
        var labelBlocks: [String: Int] = [:]
        for session in windowSessions {
            labelSeconds[session.label, default: 0] += session.activeSeconds
            labelBlocks[session.label, default: 0] += 1
        }
        let byLabel = labelSeconds
            .map { LabelUsage(label: $0.key, seconds: $0.value, blocks: labelBlocks[$0.key] ?? 0) }
            .sorted { $0.seconds > $1.seconds }

        return Insights(
            todayActive: todayActive,
            todayBlocks: todaySessions.count,
            streakDays: streak,
            windowActive: windowActive,
            windowBlocks: windowSessions.count,
            daily: daily,
            byApp: byApp,
            byLabel: byLabel
        )
    }
}
