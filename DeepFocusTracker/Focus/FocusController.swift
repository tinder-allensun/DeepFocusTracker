import Foundation
import SwiftData
import Observation

/// Owns the lifecycle of the active focus block: opens/closes `FocusSession`
/// records, drives the live menu-bar counter, and (via `ActivityMonitor`)
/// records per-app usage. It records only — no focus/distraction judgment.
@MainActor
@Observable
final class FocusController {
    private let context: ModelContext
    private let monitor: ActivityMonitor

    /// The currently running session, or nil when idle.
    private(set) var activeSession: FocusSession?

    /// Updated once per second while a block runs; drives the live counter and
    /// the live per-app tallies.
    private(set) var tick: Date = .now

    /// Set when a block ends so the popover can show its summary.
    private(set) var lastFinishedSession: FocusSession?
    private(set) var lastSummary: UsageSummary?

    @ObservationIgnored private var timer: Timer?

    init(context: ModelContext, idleTimeout: TimeInterval = 120) {
        self.context = context
        self.monitor = ActivityMonitor(idleTimeout: idleTimeout)
        self.activeSession = Self.fetchOpenSession(in: context)
        Self.seedDefaultLabelsIfNeeded(in: context)
        if activeSession != nil {
            monitor.start()
            startTicking()
        }
    }

    var isRunning: Bool { activeSession != nil }

    /// Live per-app usage for the running block (refreshes with `tick`).
    var liveUsage: UsageSummary {
        guard activeSession != nil else { return .empty }
        return monitor.snapshot(asOf: tick)
    }

    /// The frontmost app right now (nil when idle/away).
    var currentAppName: String? { monitor.currentAppName }

    /// Title for the menu-bar status item, or nil when idle.
    /// - Target set: counts **down** toward the target, then shows `+overtime`.
    /// - No target: counts **up** from the start.
    var menuBarTitle: String? {
        guard let session = activeSession else { return nil }
        let elapsed = session.elapsed(asOf: tick)
        guard let target = session.targetDuration else {
            return TimeFormat.clock(elapsed)
        }
        let remaining = target - elapsed
        return remaining >= 0
            ? TimeFormat.clock(remaining)
            : "+" + TimeFormat.clock(-remaining)
    }

    /// Start a new focus block. No-op if one is already running.
    func start(label: String, targetDuration: TimeInterval? = nil, now: Date = .now) {
        guard activeSession == nil else { return }
        lastFinishedSession = nil
        lastSummary = nil
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = FocusSession(
            label: trimmed.isEmpty ? "Focus" : trimmed,
            start: now,
            targetDuration: targetDuration
        )
        context.insert(session)
        try? context.save()
        activeSession = session
        monitor.start(now: now)
        startTicking()
    }

    /// End the active focus block: persist the recorded intervals, cache the
    /// active/away totals, and surface the summary. No-op if nothing is running.
    func stop(now: Date = .now) {
        guard let session = activeSession else { return }
        let result = monitor.stop(now: now)
        stopTicking()

        for span in result.spans {
            context.insert(AppInterval(
                sessionID: session.id,
                appBundleID: span.bundleID,
                appName: span.appName,
                start: span.start,
                duration: span.duration
            ))
        }
        let summary = UsageAggregator.summarize(
            spans: result.spans,
            awaySeconds: result.awaySeconds,
            switchCount: result.switchCount
        )
        session.end = now
        session.activeSeconds = summary.activeSeconds
        session.awaySeconds = summary.awaySeconds
        try? context.save()

        lastFinishedSession = session
        lastSummary = summary
        activeSession = nil
    }

    /// Dismiss the end-of-block summary and return to the idle view.
    func dismissSummary() {
        lastFinishedSession = nil
        lastSummary = nil
    }

    // MARK: - Live ticking

    private func startTicking() {
        stopTicking()
        tick = .now
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick = .now }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Setup helpers

    private static func fetchOpenSession(in context: ModelContext) -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.first { $0.end == nil }
    }

    private static func seedDefaultLabelsIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<SessionLabel>())) ?? 0
        guard existing == 0 else { return }
        let defaults: [(name: String, color: String)] = [
            ("Writing", "#4C8DFF"),
            ("Coding", "#34C759"),
            ("Reading", "#FF9F0A"),
            ("Email", "#AF52DE"),
        ]
        for entry in defaults {
            context.insert(SessionLabel(name: entry.name, colorHex: entry.color))
        }
        try? context.save()
    }
}
