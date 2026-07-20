import Testing
import Foundation
import SwiftData
@testable import DeepFocusTracker

/// `SessionHistory.delete` is the one correct delete path. Because `AppInterval`
/// links by a plain `sessionID` (no SwiftData relationship, no cascade), delete
/// must remove the intervals itself and decrement the rollups — or the dashboard
/// drifts. These tests guard both.
@MainActor
struct SessionHistoryTests {

    /// Inserts a finished block plus its intervals and matching rollups, mirroring
    /// what `FocusController.stop()` persists. Uses `.current` (as the real delete
    /// path does) so the rollup day-key matches on remove.
    private func makeBlock(label: String, start: Date, apps: [(bundle: String, seconds: TimeInterval)], in context: ModelContext) -> FocusSession {
        let active = apps.reduce(0) { $0 + $1.seconds }
        let session = FocusSession(label: label, start: start)
        session.end = start.addingTimeInterval(active)
        session.activeSeconds = active
        session.awaySeconds = 0
        session.switchCount = max(0, apps.count - 1)
        context.insert(session)
        var cursor = start
        for app in apps {
            context.insert(AppInterval(sessionID: session.id, appBundleID: app.bundle, appName: app.bundle, start: cursor, duration: app.seconds))
            cursor = cursor.addingTimeInterval(app.seconds)
        }
        Rollups.add(day: start, activeSeconds: active, awaySeconds: 0,
                    perApp: apps.map { AppUsage(bundleID: $0.bundle, appName: $0.bundle, seconds: $0.seconds) },
                    in: context)
        return session
    }

    @Test func deleteRemovesTheSessionItsIntervalsAndItsRollupContribution() throws {
        let context = TestStore.makeContext()
        let session = makeBlock(label: "Coding", start: utcDate(2026, 4, 1, hour: 9),
                                apps: [("com.a", 600), ("com.b", 400)], in: context)
        try context.save()

        SessionHistory.delete(session, in: context)

        #expect(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AppInterval>()).isEmpty)   // no orphaned intervals
        #expect(try context.fetch(FetchDescriptor<DayRollup>()).isEmpty)     // rollup decremented to empty
        #expect(try context.fetch(FetchDescriptor<DayAppRollup>()).isEmpty)
    }

    @Test func deleteLeavesOtherSessionsAndTheirIntervalsIntact() throws {
        let context = TestStore.makeContext()
        let doomed = makeBlock(label: "A", start: utcDate(2026, 4, 1, hour: 9), apps: [("com.a", 600)], in: context)
        let keeper = makeBlock(label: "B", start: utcDate(2026, 4, 2, hour: 9), apps: [("com.b", 300), ("com.c", 200)], in: context)
        try context.save()

        SessionHistory.delete(doomed, in: context)

        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == keeper.id)

        let keeperID = keeper.id
        let intervals = try context.fetch(FetchDescriptor<AppInterval>())
        #expect(intervals.count == 2)                              // only the keeper's two intervals remain
        #expect(intervals.allSatisfy { $0.sessionID == keeperID }) // none orphaned from the deleted block
    }
}
