import Foundation
import SwiftData

/// Maintains the denormalized daily rollups (`DayRollup`, `DayAppRollup`) that let
/// the dashboard read O(days) rows instead of scanning the full session / interval
/// tables. Called at block end (`add`) and on delete (`remove`) on the main
/// context — each call touches only the block's day, so it stays cheap.
///
/// Upserts must *accumulate*, and `#Unique`'s collision behavior *replaces*, so we
/// fetch-or-create and add/subtract by hand rather than relying on it.
enum Rollups {
    /// Fold a finished block's totals into its day's rollups.
    static func add(
        day: Date,
        activeSeconds: TimeInterval,
        awaySeconds: TimeInterval,
        perApp: [AppUsage],
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let key = calendar.startOfDay(for: day)
        let rollup = fetchOrCreateDay(key, in: context)
        rollup.activeSeconds += activeSeconds
        rollup.awaySeconds += awaySeconds
        rollup.blockCount += 1
        for app in perApp {
            let appRollup = fetchOrCreateApp(day: key, bundleID: app.bundleID, appName: app.appName, in: context)
            appRollup.seconds += app.seconds
        }
    }

    /// Subtract a deleted block's totals from its day's rollups, removing rows
    /// that drop to empty so the tables stay tidy.
    static func remove(
        day: Date,
        activeSeconds: TimeInterval,
        awaySeconds: TimeInterval,
        perApp: [AppUsage],
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let key = calendar.startOfDay(for: day)
        if let rollup = fetchDay(key, in: context) {
            rollup.activeSeconds = max(0, rollup.activeSeconds - activeSeconds)
            rollup.awaySeconds = max(0, rollup.awaySeconds - awaySeconds)
            rollup.blockCount -= 1
            if rollup.blockCount <= 0 { context.delete(rollup) }
        }
        for app in perApp {
            guard let appRollup = fetchApp(day: key, bundleID: app.bundleID, in: context) else { continue }
            let remaining = appRollup.seconds - app.seconds
            if remaining > 0.5 {
                appRollup.seconds = remaining
            } else {
                context.delete(appRollup)
            }
        }
    }

    // MARK: - Fetch-or-create

    private static func fetchDay(_ day: Date, in context: ModelContext) -> DayRollup? {
        var descriptor = FetchDescriptor<DayRollup>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchOrCreateDay(_ day: Date, in context: ModelContext) -> DayRollup {
        if let existing = fetchDay(day, in: context) { return existing }
        let created = DayRollup(day: day)
        context.insert(created)
        return created
    }

    private static func fetchApp(day: Date, bundleID: String, in context: ModelContext) -> DayAppRollup? {
        var descriptor = FetchDescriptor<DayAppRollup>(
            predicate: #Predicate { $0.day == day && $0.bundleID == bundleID }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchOrCreateApp(day: Date, bundleID: String, appName: String, in context: ModelContext) -> DayAppRollup {
        if let existing = fetchApp(day: day, bundleID: bundleID, in: context) { return existing }
        let created = DayAppRollup(day: day, bundleID: bundleID, appName: appName)
        context.insert(created)
        return created
    }
}
