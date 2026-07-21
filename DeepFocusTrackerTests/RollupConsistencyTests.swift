import Testing
import Foundation
import SwiftData
@testable import DeepFocusCore

/// The dashboard trusts the denormalized rollups, not the raw tables — so the
/// rollups must always equal what a full recompute from the raw rows would give.
/// This end-to-end guardrail seeds a store, then recomputes per-day totals from
/// the raw `FocusSession` / `AppInterval` rows and asserts the rollups agree. If a
/// future change to the write paths lets them drift, these fail.
@MainActor
struct RollupConsistencyTests {

    private let now = utcDate(2026, 6, 15, hour: 12)
    private let cal = Calendar.testUTC

    @Test func dayRollupsEqualRawSessionTotals() throws {
        let context = TestStore.makeContext()
        TestDataSeeder.seed(sessionCount: 60, in: context, now: now, calendar: cal)

        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        var expectedActive: [Date: TimeInterval] = [:]
        var expectedAway: [Date: TimeInterval] = [:]
        var expectedBlocks: [Date: Int] = [:]
        for session in sessions {
            let day = cal.startOfDay(for: session.start)
            expectedActive[day, default: 0] += session.activeSeconds
            expectedAway[day, default: 0] += session.awaySeconds
            expectedBlocks[day, default: 0] += 1
        }

        let rollups = try context.fetch(FetchDescriptor<DayRollup>())
        #expect(rollups.count == expectedActive.count)
        for rollup in rollups {
            #expect(rollup.activeSeconds == expectedActive[rollup.day])
            #expect(rollup.awaySeconds == expectedAway[rollup.day])
            #expect(rollup.blockCount == expectedBlocks[rollup.day])
        }
    }

    @Test func perAppRollupsEqualRawIntervalTotals() throws {
        let context = TestStore.makeContext()
        TestDataSeeder.seed(sessionCount: 60, in: context, now: now, calendar: cal)

        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        let dayOf = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, cal.startOfDay(for: $0.start)) })

        var expected: [String: TimeInterval] = [:]  // "day|bundle" → seconds
        for interval in try context.fetch(FetchDescriptor<AppInterval>()) {
            guard let day = dayOf[interval.sessionID] else { continue }
            expected["\(day.timeIntervalSinceReferenceDate)|\(interval.appBundleID)", default: 0] += interval.duration
        }

        let appRollups = try context.fetch(FetchDescriptor<DayAppRollup>())
        #expect(appRollups.count == expected.count)
        for rollup in appRollups {
            #expect(rollup.seconds == expected["\(rollup.day.timeIntervalSinceReferenceDate)|\(rollup.bundleID)"])
        }
    }
}
