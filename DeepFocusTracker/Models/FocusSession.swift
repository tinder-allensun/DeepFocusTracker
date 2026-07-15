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
    /// The inline default (`= 0`) gives the SwiftData attribute a default value
    /// so lightweight store migrations can populate existing rows.
    var activeSeconds: TimeInterval = 0
    /// Time the user was idle / away, cached when the block ends.
    var awaySeconds: TimeInterval = 0
    /// Number of frontmost-app switches during the block, cached when it ends.
    /// The inline default (`= 0`) gives the attribute a value so lightweight
    /// migrations can populate existing rows (which read back as 0).
    var switchCount: Int = 0

    init(label: String, start: Date, targetDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.label = label
        self.start = start
        self.end = nil
        self.targetDuration = targetDuration
        self.activeSeconds = 0
        self.awaySeconds = 0
        self.switchCount = 0
    }

    var isRunning: Bool { end == nil }

    /// Total elapsed wall-clock time (uses `end` when finished, else `now`).
    func elapsed(asOf now: Date = .now) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}
