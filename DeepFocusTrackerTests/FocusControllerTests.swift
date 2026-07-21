import Testing
import Foundation
import SwiftData
@testable import DeepFocusCore

/// `FocusController` owns the block lifecycle. It's `@MainActor` and drives an
/// `ActivityMonitor`, but with an injected `now` the store side effects are
/// deterministic: no app-switch / idle events fire under test (the run loop isn't
/// spun), so a block start→stop yields one continuous span == the elapsed time.
///
/// Note: `menuBarTitle` reads the live `tick` (wall-clock), so it's verified by
/// driving the running app rather than here (see CONTRIBUTING.md). The countdown
/// math it wraps is `FocusSession.elapsed` + `TimeFormat.clock`, both tested.
@MainActor
struct FocusControllerTests {

    @Test func startOpensASession() throws {
        let context = TestStore.makeContext()
        let controller = FocusController(context: context)
        #expect(controller.isRunning == false)

        controller.start(label: "Coding", now: utcDate(2026, 5, 1, hour: 9))
        #expect(controller.isRunning)
        #expect(controller.activeSession?.label == "Coding")
        #expect(controller.activeSession?.end == nil)
        #expect(try context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.end == nil })).count == 1)

        controller.stop(now: utcDate(2026, 5, 1, hour: 9, minute: 25))  // clean up the live timer
    }

    @Test func aSecondStartWhileRunningIsIgnored() {
        let context = TestStore.makeContext()
        let controller = FocusController(context: context)
        controller.start(label: "First", now: utcDate(2026, 5, 1, hour: 9))
        let firstID = controller.activeSession?.id

        controller.start(label: "Second", now: utcDate(2026, 5, 1, hour: 9, minute: 5))
        #expect(controller.activeSession?.id == firstID)
        #expect(controller.activeSession?.label == "First")

        controller.stop(now: utcDate(2026, 5, 1, hour: 10))
    }

    @Test func stopCachesTotalsAndWritesIntervalsAndRollup() throws {
        let context = TestStore.makeContext()
        let controller = FocusController(context: context)
        let start = utcDate(2026, 5, 1, hour: 9)
        controller.start(label: "Coding", now: start)
        controller.stop(now: start.addingTimeInterval(1500))  // 25 minutes

        #expect(controller.isRunning == false)
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.end == start.addingTimeInterval(1500))
        #expect(session.activeSeconds == 1500)  // single continuous span, nothing away
        #expect(session.awaySeconds == 0)
        #expect(session.switchCount == 0)

        #expect(try context.fetch(FetchDescriptor<AppInterval>()).count == 1)
        let days = try context.fetch(FetchDescriptor<DayRollup>())
        #expect(days.count == 1)
        #expect(days[0].activeSeconds == 1500)
        #expect(days[0].blockCount == 1)
        #expect(controller.lastSummary?.activeSeconds == 1500)
    }

    @Test func freshStoreIsSeededWithDefaultLabels() throws {
        let context = TestStore.makeContext()
        _ = FocusController(context: context)
        let names = try context.fetch(FetchDescriptor<SessionLabel>()).map(\.name).sorted()
        #expect(names == ["Coding", "Email", "Reading", "Writing"])
    }

    @Test func startBumpsAnExistingLabelCaseInsensitivelyWithoutDuplicating() throws {
        let context = TestStore.makeContext()
        let controller = FocusController(context: context)  // seeds Writing / Coding / Reading / Email
        #expect(try context.fetch(FetchDescriptor<SessionLabel>()).first { $0.name == "Coding" }?.lastUsed == nil)

        controller.start(label: "coding", now: utcDate(2026, 5, 1, hour: 9))  // lower-case on purpose
        controller.stop(now: utcDate(2026, 5, 1, hour: 10))

        let labels = try context.fetch(FetchDescriptor<SessionLabel>())
        #expect(labels.count == 4)  // matched "Coding" — no near-duplicate spawned
        #expect(labels.first { $0.name == "Coding" }?.lastUsed != nil)  // and bumped
    }

    @Test func startWithANewLabelAddsItToTheCatalog() throws {
        let context = TestStore.makeContext()
        let controller = FocusController(context: context)
        controller.start(label: "Research", now: utcDate(2026, 5, 1, hour: 9))
        controller.stop(now: utcDate(2026, 5, 1, hour: 10))

        let labels = try context.fetch(FetchDescriptor<SessionLabel>())
        #expect(labels.count == 5)  // 4 seeds + Research
        #expect(labels.first { $0.name == "Research" }?.lastUsed != nil)
    }

    @Test func deleteLabelDropsTheChipButNotRecordedSessions() throws {
        let context = TestStore.makeContext()
        let controller = FocusController(context: context)
        controller.start(label: "Coding", now: utcDate(2026, 5, 1, hour: 9))
        controller.stop(now: utcDate(2026, 5, 1, hour: 10))

        let coding = try #require(try context.fetch(FetchDescriptor<SessionLabel>()).first { $0.name == "Coding" })
        controller.deleteLabel(coding)

        #expect(!(try context.fetch(FetchDescriptor<SessionLabel>()).contains { $0.name == "Coding" }))
        // The recorded session keeps its label (stored as a plain string copy).
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.label == "Coding")
    }

    @Test func anOpenSessionFromAPriorLaunchIsRecoveredOnInit() throws {
        let context = TestStore.makeContext()
        let session = FocusSession(label: "Interrupted", start: utcDate(2026, 5, 1, hour: 9))
        context.insert(session)  // no `end` → an open block, as if a prior launch crashed
        try context.save()

        let controller = FocusController(context: context)
        #expect(controller.isRunning)
        #expect(controller.activeSession?.label == "Interrupted")

        controller.stop(now: utcDate(2026, 5, 1, hour: 10))
        #expect(controller.isRunning == false)
    }

    /// `FocusSession.elapsed` underpins both the live timer and the countdown; it's
    /// pure (takes an explicit `now`), so it's pinned directly here.
    @Test func sessionElapsedUsesEndWhenFinishedOtherwiseNow() {
        let start = utcDate(2026, 5, 1, hour: 9)
        let session = FocusSession(label: "X", start: start)
        #expect(session.isRunning)
        #expect(session.elapsed(asOf: start.addingTimeInterval(100)) == 100)  // running → measured to `now`

        session.end = start.addingTimeInterval(300)
        #expect(session.isRunning == false)
        #expect(session.elapsed(asOf: start.addingTimeInterval(9_999)) == 300) // finished → frozen at `end`
    }
}
