import Foundation
import SwiftData
import Observation

/// Owns the lifecycle of the active focus block and exposes it to the UI.
/// For M1 it simply opens and closes `FocusSession` records; app-usage
/// measurement, scoring, and nudges arrive in later milestones.
@MainActor
@Observable
final class FocusController {
    private let context: ModelContext

    /// The currently running session, or nil when idle.
    private(set) var activeSession: FocusSession?

    init(context: ModelContext) {
        self.context = context
        // Recover a session left open if the app previously quit mid-block.
        self.activeSession = Self.fetchOpenSession(in: context)
        Self.seedDefaultLabelsIfNeeded(in: context)
    }

    var isRunning: Bool { activeSession != nil }

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
    }

    /// End the active focus block. No-op if nothing is running.
    func stop(now: Date = .now) {
        guard let session = activeSession else { return }
        session.end = now
        try? context.save()
        activeSession = nil
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
