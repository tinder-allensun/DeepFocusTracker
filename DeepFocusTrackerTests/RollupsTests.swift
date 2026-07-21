import Testing
import Foundation
import SwiftData
@testable import DeepFocusCore

/// `Rollups` maintains the denormalized daily tables the dashboard trusts. The
/// invariant that matters most: upserts must **accumulate**, never replace (see
/// ARCHITECTURE.md "Scalability & rollups"). Each test uses its own in-memory
/// store and a fixed UTC calendar so day-keys are deterministic.
@MainActor
struct RollupsTests {

    private func usage(_ bundle: String, _ seconds: TimeInterval) -> AppUsage {
        AppUsage(bundleID: bundle, appName: bundle, seconds: seconds)
    }

    @Test func addCreatesDayAndPerAppRollups() throws {
        let context = TestStore.makeContext()
        let day = utcDate(2026, 3, 10, hour: 9)
        Rollups.add(day: day, activeSeconds: 1000, awaySeconds: 200,
                    perApp: [usage("com.a", 700), usage("com.b", 300)],
                    in: context, calendar: .testUTC)
        try context.save()

        let dayRollups = try context.fetch(FetchDescriptor<DayRollup>())
        #expect(dayRollups.count == 1)
        #expect(dayRollups[0].activeSeconds == 1000)
        #expect(dayRollups[0].awaySeconds == 200)
        #expect(dayRollups[0].blockCount == 1)
        #expect(dayRollups[0].day == Calendar.testUTC.startOfDay(for: day))  // keyed by start-of-day
        #expect(try context.fetch(FetchDescriptor<DayAppRollup>()).count == 2)
    }

    @Test func addAccumulatesAcrossBlocksOnTheSameDay() throws {
        let context = TestStore.makeContext()
        let day = utcDate(2026, 3, 10, hour: 9)
        Rollups.add(day: day, activeSeconds: 1000, awaySeconds: 100, perApp: [usage("com.a", 1000)], in: context, calendar: .testUTC)
        try context.save()
        Rollups.add(day: day, activeSeconds: 500, awaySeconds: 50, perApp: [usage("com.a", 500)], in: context, calendar: .testUTC)
        try context.save()

        let days = try context.fetch(FetchDescriptor<DayRollup>())
        #expect(days.count == 1)
        #expect(days[0].activeSeconds == 1500)  // accumulated, NOT replaced — the core invariant
        #expect(days[0].awaySeconds == 150)
        #expect(days[0].blockCount == 2)
        let apps = try context.fetch(FetchDescriptor<DayAppRollup>())
        #expect(apps.count == 1)
        #expect(apps[0].seconds == 1500)
    }

    @Test func addKeepsDifferentDaysSeparate() throws {
        let context = TestStore.makeContext()
        Rollups.add(day: utcDate(2026, 3, 10, hour: 9), activeSeconds: 1000, awaySeconds: 0, perApp: [], in: context, calendar: .testUTC)
        Rollups.add(day: utcDate(2026, 3, 11, hour: 9), activeSeconds: 2000, awaySeconds: 0, perApp: [], in: context, calendar: .testUTC)
        try context.save()

        let days = try context.fetch(FetchDescriptor<DayRollup>()).sorted { $0.day < $1.day }
        #expect(days.count == 2)
        #expect(days[0].activeSeconds == 1000)
        #expect(days[1].activeSeconds == 2000)
    }

    @Test func removeDeletesRowsThatDropToEmpty() throws {
        let context = TestStore.makeContext()
        let day = utcDate(2026, 3, 10, hour: 9)
        let perApp = [usage("com.a", 1000)]
        Rollups.add(day: day, activeSeconds: 1000, awaySeconds: 100, perApp: perApp, in: context, calendar: .testUTC)
        try context.save()
        Rollups.remove(day: day, activeSeconds: 1000, awaySeconds: 100, perApp: perApp, in: context, calendar: .testUTC)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DayRollup>()).isEmpty)     // blockCount hit 0 → row removed
        #expect(try context.fetch(FetchDescriptor<DayAppRollup>()).isEmpty)  // seconds hit 0 → row removed
    }

    @Test func removeOneOfTwoBlocksLeavesTheRemainder() throws {
        let context = TestStore.makeContext()
        let day = utcDate(2026, 3, 10, hour: 9)
        Rollups.add(day: day, activeSeconds: 1000, awaySeconds: 100, perApp: [usage("com.a", 1000)], in: context, calendar: .testUTC)
        try context.save()
        Rollups.add(day: day, activeSeconds: 400, awaySeconds: 40, perApp: [usage("com.a", 400)], in: context, calendar: .testUTC)
        try context.save()
        Rollups.remove(day: day, activeSeconds: 400, awaySeconds: 40, perApp: [usage("com.a", 400)], in: context, calendar: .testUTC)
        try context.save()

        let days = try context.fetch(FetchDescriptor<DayRollup>())
        #expect(days.count == 1)
        #expect(days[0].activeSeconds == 1000)
        #expect(days[0].blockCount == 1)
        let apps = try context.fetch(FetchDescriptor<DayAppRollup>())
        #expect(apps.count == 1)
        #expect(apps[0].seconds == 1000)
    }

    @Test func removeIsANoOpWhenNothingWasRecordedForThatDay() throws {
        let context = TestStore.makeContext()
        // Removing from an empty store must not crash or create negative rows.
        Rollups.remove(day: utcDate(2026, 3, 10, hour: 9), activeSeconds: 500, awaySeconds: 50,
                       perApp: [usage("com.a", 500)], in: context, calendar: .testUTC)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DayRollup>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DayAppRollup>()).isEmpty)
    }
}
