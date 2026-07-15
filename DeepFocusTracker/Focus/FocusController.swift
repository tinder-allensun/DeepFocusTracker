import Foundation
import SwiftData
import Observation

/// Owns the lifecycle of the active focus block and exposes it to the UI.
/// For M1 it opens and closes `FocusSession` records and drives the live
/// menu-bar counter; app-usage measurement, scoring, and nudges arrive later.
@MainActor
@Observable
final class FocusController {
    private let context: ModelContext

    /// The currently running session, or nil when idle.
    private(set) var activeSession: FocusSession?

    /// Updated once per second while a block runs. Views that read this (via
    /// `menuBarTitle`) re-render on each tick, driving the live counter.
    private(set) var tick: Date = .now

    @ObservationIgnored private var timer: Timer?

    init(context: ModelContext) {
        self.context = context
        // Recover a session left open if the app previously quit mid-block.
        self.activeSession = Self.fetchOpenSession(in: context)
        Self.seedDefaultLabelsIfNeeded(in: context)
        if activeSession != nil {
            startTicking()
        }
    }

    var isRunning: Bool { activeSession != nil }

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
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = FocusSession(
            label: trimmed.isEmpty ? "Focus" : trimmed,
            start: now,
            targetDuration: targetDuration
        )
        context.insert(session)
        try? context.save()
        activeSession = session
        startTicking()
    }

    /// End the active focus block. No-op if nothing is running.
    func stop(now: Date = .now) {
        guard let session = activeSession else { return }
        stopTicking()
        session.end = now
        try? context.save()
        activeSession = nil
    }

    // MARK: - Live ticking

    private func startTicking() {
        stopTicking()
        tick = .now
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick = .now
        }
        // .common mode so the counter keeps advancing while the menu/popover is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Setup helpers

    private static func fetchOpenSession(in context: ModelContext) -> FocusSession? {
        // Small data set: fetch recent sessions and pick any still open, which
        // avoids `== nil` predicate edge cases.
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
