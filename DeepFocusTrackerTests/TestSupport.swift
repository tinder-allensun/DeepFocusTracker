import Foundation
import SwiftData
@testable import DeepFocusTracker

/// Shared helpers for the test suite. Kept tiny and dependency-free so tests read
/// as value-in / value-out.
enum TestStore {
    private static let schema = Schema([
        FocusSession.self,
        AppInterval.self,
        SessionLabel.self,
        DayRollup.self,
        DayAppRollup.self,
    ])

    /// **One** in-memory container for the whole test process, reused by every
    /// test. This is deliberate: creating a *second* `ModelContainer` over the same
    /// `@Model` types in one process makes CoreData trap ("multiple
    /// NSEntityDescriptions claim the NSManagedObject subclass"), so per-test
    /// containers crash. Sharing one is safe here because every SwiftData suite is
    /// `@MainActor` — their tests never run concurrently — and each test starts
    /// from a clean store via `makeContext()`.
    @MainActor
    static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Force-try: a container failure here is a genuine test failure.
        return try! ModelContainer(for: schema, configurations: config)
    }()

    /// A fresh context on the shared container with the store wiped first, so each
    /// test sees an empty store and nothing leaks between tests. (Deletes row by
    /// row rather than a batch delete, which isn't supported on in-memory stores.)
    @MainActor
    static func makeContext() -> ModelContext {
        let context = ModelContext(shared)
        for session in (try? context.fetch(FetchDescriptor<FocusSession>())) ?? [] { context.delete(session) }
        for interval in (try? context.fetch(FetchDescriptor<AppInterval>())) ?? [] { context.delete(interval) }
        for label in (try? context.fetch(FetchDescriptor<SessionLabel>())) ?? [] { context.delete(label) }
        for rollup in (try? context.fetch(FetchDescriptor<DayRollup>())) ?? [] { context.delete(rollup) }
        for rollup in (try? context.fetch(FetchDescriptor<DayAppRollup>())) ?? [] { context.delete(rollup) }
        try? context.save()
        return context
    }
}

extension Calendar {
    /// A fixed UTC Gregorian calendar so date math in tests is deterministic
    /// regardless of the machine's locale / time zone. Pair with `Self.utcDate`.
    static var testUTC: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}

/// Builds a UTC `Date` from components — the readable way to pin "days" in the
/// insight/rollup tests without depending on the machine's time zone.
func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    return Calendar.testUTC.date(from: comps)!
}
