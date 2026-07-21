import Foundation

/// A completed block's label + active time, for the by-label rollup. Kept as a
/// plain value so aggregation stays free of SwiftUI/SwiftData.
struct SessionRecord {
    let start: Date
    let end: Date
    let label: String
    let activeSeconds: TimeInterval
    let awaySeconds: TimeInterval
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A day's rolled-up totals (value form of `DayRollup`).
struct DayStat {
    let day: Date
    let activeSeconds: TimeInterval
    let awaySeconds: TimeInterval
    let blockCount: Int
}

/// A day's per-app rolled-up active seconds (value form of `DayAppRollup`).
struct AppDayStat {
    let day: Date
    let bundleID: String
    let appName: String
    let seconds: TimeInterval
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

/// Pure aggregation of the denormalized daily rollups (plus windowed sessions for
/// the by-label view) into dashboard figures. Reads O(days) rollup rows rather
/// than scanning every session / interval; deterministic given its inputs
/// (`now` / `calendar` are injected).
enum InsightsService {
    static func compute(
        days: [DayStat],
        appDays: [AppDayStat],
        sessions: [SessionRecord],
        now: Date = .now,
        calendar: Calendar = .current,
        trailingDays: Int = 14
    ) -> Insights {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(trailingDays - 1), to: today) ?? today

        // Today
        let todayStat = days.first { calendar.isDate($0.day, inSameDayAs: now) }
        let todayActive = todayStat?.activeSeconds ?? 0
        let todayBlocks = todayStat?.blockCount ?? 0

        // Window
        let windowDays = days.filter { $0.day >= windowStart }
        let windowActive = windowDays.reduce(0) { $0 + $1.activeSeconds }
        let windowBlocks = windowDays.reduce(0) { $0 + $1.blockCount }

        // Daily buckets (one entry per day in the window, oldest → newest)
        var byDay: [Date: TimeInterval] = [:]
        for day in windowDays {
            byDay[calendar.startOfDay(for: day.day), default: 0] += day.activeSeconds
        }
        var daily: [DayActive] = []
        for offset in stride(from: trailingDays - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            daily.append(DayActive(date: date, seconds: byDay[date] ?? 0))
        }

        // Current streak: consecutive days (ending today, or yesterday if today
        // is empty) that have at least one block.
        let daysWithBlocks = Set(days.filter { $0.blockCount > 0 }.map { calendar.startOfDay(for: $0.day) })
        var streak = 0
        var cursor = daysWithBlocks.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while daysWithBlocks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        // Per-app (window): sum the per-day-per-app rollups by bundle.
        let windowApps = appDays.filter { $0.day >= windowStart }
        var appTotals: [String: (name: String, seconds: TimeInterval)] = [:]
        for app in windowApps {
            let running = appTotals[app.bundleID]?.seconds ?? 0
            appTotals[app.bundleID] = (app.appName, running + app.seconds)
        }
        let byApp = Array(
            appTotals
                .map { AppUsage(bundleID: $0.key, appName: $0.value.name, seconds: $0.value.seconds) }
                .sorted { $0.seconds > $1.seconds }
                .prefix(8)
        )

        // Per-label (window): from the windowed session rows.
        var labelSeconds: [String: TimeInterval] = [:]
        var labelBlocks: [String: Int] = [:]
        for session in sessions where session.start >= windowStart {
            labelSeconds[session.label, default: 0] += session.activeSeconds
            labelBlocks[session.label, default: 0] += 1
        }
        let byLabel = labelSeconds
            .map { LabelUsage(label: $0.key, seconds: $0.value, blocks: labelBlocks[$0.key] ?? 0) }
            .sorted { $0.seconds > $1.seconds }

        return Insights(
            todayActive: todayActive,
            todayBlocks: todayBlocks,
            streakDays: streak,
            windowActive: windowActive,
            windowBlocks: windowBlocks,
            daily: daily,
            byApp: byApp,
            byLabel: byLabel
        )
    }
}
