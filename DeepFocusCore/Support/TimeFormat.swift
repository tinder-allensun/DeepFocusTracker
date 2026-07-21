import Foundation

/// Formats a duration as a clock string: `MM:SS`, or `H:MM:SS` past an hour.
enum TimeFormat {
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Formats a duration compactly *with its unit* — `45s`, `25m`, `1h 20m` — for
    /// aggregate totals in the dashboard and post-block summaries. Unlike `clock`,
    /// the unit lives in the string (so a total can't be misread as a stopwatch),
    /// and it's rounded to a sensible granularity: seconds under a minute, whole
    /// minutes otherwise. Use `clock` only for the live, ticking menu-bar timer.
    static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}
