import Foundation
import SwiftData

/// A single focus block: the user declares intent by starting it, and the
/// tracker fills in the measured breakdown while it runs (measurement lands
/// in a later milestone).
@Model
final class FocusSession {
    var id: UUID
    var label: String
    var start: Date
    var end: Date?
    /// Target length in seconds, if the user set one.
    var targetDuration: TimeInterval?

    // Measured breakdown — populated by the activity tracker (M2).
    var focusedSeconds: TimeInterval
    var neutralSeconds: TimeInterval
    var distractedSeconds: TimeInterval
    var idleSeconds: TimeInterval
    var nudgeCount: Int

    init(label: String, start: Date, targetDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.label = label
        self.start = start
        self.end = nil
        self.targetDuration = targetDuration
        self.focusedSeconds = 0
        self.neutralSeconds = 0
        self.distractedSeconds = 0
        self.idleSeconds = 0
        self.nudgeCount = 0
    }

    var isRunning: Bool { end == nil }

    /// Total elapsed wall-clock time (uses `end` when finished, else `now`).
    func elapsed(asOf now: Date = .now) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }

    /// Fraction of measured *active* time that was focused (0...1). Neutral and
    /// idle time are excluded from the denominator.
    var focusScore: Double {
        let denominator = focusedSeconds + distractedSeconds
        guard denominator > 0 else { return 0 }
        return focusedSeconds / denominator
    }
}
