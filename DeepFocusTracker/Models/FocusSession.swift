import Foundation
import SwiftData

/// A single focus block. The per-app breakdown is derived from the session's
/// `AppInterval`s; `activeSeconds` / `awaySeconds` are cached at stop for fast
/// dashboard rollups later.
@Model
final class FocusSession {
    var id: UUID
    var label: String
    var start: Date
    var end: Date?
    /// Target length in seconds, if the user set one.
    var targetDuration: TimeInterval?

    /// Time attributed to apps (non-idle), cached when the block ends.
    var activeSeconds: TimeInterval
    /// Time the user was idle / away, cached when the block ends.
    var awaySeconds: TimeInterval

    init(label: String, start: Date, targetDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.label = label
        self.start = start
        self.end = nil
        self.targetDuration = targetDuration
        self.activeSeconds = 0
        self.awaySeconds = 0
    }

    var isRunning: Bool { end == nil }

    /// Total elapsed wall-clock time (uses `end` when finished, else `now`).
    func elapsed(asOf now: Date = .now) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}
