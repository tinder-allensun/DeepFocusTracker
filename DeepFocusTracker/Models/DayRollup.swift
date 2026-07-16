import Foundation
import SwiftData

/// Per-day denormalized totals, maintained incrementally at block end and
/// decremented on delete. The dashboard reads these (O(days) rows) instead of
/// scanning every session — this is the app's scalability mechanism. One row per
/// active day; `day` is the local start-of-day.
@Model
final class DayRollup {
    @Attribute(.unique) var day: Date
    var activeSeconds: TimeInterval = 0
    var awaySeconds: TimeInterval = 0
    var blockCount: Int = 0

    init(day: Date, activeSeconds: TimeInterval = 0, awaySeconds: TimeInterval = 0, blockCount: Int = 0) {
        self.day = day
        self.activeSeconds = activeSeconds
        self.awaySeconds = awaySeconds
        self.blockCount = blockCount
    }
}
