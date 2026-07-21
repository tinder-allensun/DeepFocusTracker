#if DEBUG
import Foundation
import SwiftData

/// Dev-only synthetic data generator for benchmarking the dashboard at scale.
///
/// Launch the built binary with `SEED_TEST_DATA=<sessionCount>` in the
/// environment to populate a *fresh* store with that many completed sessions
/// (spread over the past year), each with a few app intervals, plus the matching
/// daily rollups. This lets us prove the dashboard stays fast with a large
/// `AppInterval` table present — because it reads rollups, not intervals.
enum TestDataSeeder {
    static func seedIfRequested(in context: ModelContext) {
        guard let raw = ProcessInfo.processInfo.environment["SEED_TEST_DATA"],
              let count = Int(raw), count > 0 else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<FocusSession>())) ?? 0
        guard existing == 0 else {
            NSLog("TestDataSeeder: store already has \(existing) sessions; skipping seed.")
            return
        }
        seed(sessionCount: count, in: context)
    }

    static func seed(sessionCount: Int, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let apps: [(bundle: String, name: String)] = [
            ("com.apple.dt.Xcode", "Xcode"),
            ("com.apple.Safari", "Safari"),
            ("com.tinyspeck.slackmacgap", "Slack"),
            ("com.apple.mail", "Mail"),
            ("com.googlecode.iterm2", "iTerm2"),
            ("com.apple.Notes", "Notes"),
        ]
        let labels = ["Coding", "Writing", "Email", "Reading"]

        // Accumulate rollups in memory, then insert once (fast, and mirrors the
        // end state of the real incremental write path).
        var dayTotals: [Date: (active: TimeInterval, away: TimeInterval, blocks: Int)] = [:]
        var appTotals: [String: (day: Date, bundle: String, name: String, seconds: TimeInterval)] = [:]

        let startOfToday = calendar.startOfDay(for: now)
        var intervalCount = 0

        for i in 0..<sessionCount {
            let dayStart = calendar.date(byAdding: .day, value: -(i % 365), to: startOfToday) ?? startOfToday
            let start = dayStart.addingTimeInterval(TimeInterval(9 * 3600 + (i % 8) * 1800))
            let numApps = 2 + (i % 4)
            let session = FocusSession(label: labels[i % labels.count], start: start)

            var cursor = start
            var active: TimeInterval = 0
            for a in 0..<numApps {
                let app = apps[(i + a) % apps.count]
                let duration = TimeInterval(300 + a * 120)
                context.insert(AppInterval(
                    sessionID: session.id,
                    appBundleID: app.bundle,
                    appName: app.name,
                    start: cursor,
                    duration: duration
                ))
                intervalCount += 1
                cursor = cursor.addingTimeInterval(duration)
                active += duration
                let key = "\(dayStart.timeIntervalSinceReferenceDate)|\(app.bundle)"
                let prev = appTotals[key]?.seconds ?? 0
                appTotals[key] = (dayStart, app.bundle, app.name, prev + duration)
            }
            let away = TimeInterval((i % 3) * 120)
            session.end = cursor.addingTimeInterval(away)
            session.activeSeconds = active
            session.awaySeconds = away
            session.switchCount = numApps - 1
            context.insert(session)

            var totals = dayTotals[dayStart] ?? (0, 0, 0)
            totals.active += active
            totals.away += away
            totals.blocks += 1
            dayTotals[dayStart] = totals
        }

        for (day, totals) in dayTotals {
            context.insert(DayRollup(day: day, activeSeconds: totals.active, awaySeconds: totals.away, blockCount: totals.blocks))
        }
        for (_, app) in appTotals {
            context.insert(DayAppRollup(day: app.day, bundleID: app.bundle, appName: app.name, seconds: app.seconds))
        }
        try? context.save()
        NSLog("TestDataSeeder: seeded \(sessionCount) sessions, \(intervalCount) intervals, \(dayTotals.count) day rollups, \(appTotals.count) app rollups.")
    }
}
#endif
