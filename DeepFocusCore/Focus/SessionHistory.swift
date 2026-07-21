import Foundation
import SwiftData

/// History-management operations over stored focus blocks. Kept out of the views
/// so the detail view and the all-sessions list share one correct delete path.
enum SessionHistory {
    /// Permanently remove a block and its recorded per-app detail.
    ///
    /// `AppInterval`s link to their session by a plain `sessionID`, **not** a
    /// SwiftData relationship, so there's no cascade — we must delete them here
    /// too. Leaving them orphaned would keep skewing the dashboard's per-app
    /// aggregate (which sums *all* intervals in the window).
    static func delete(_ session: FocusSession, in context: ModelContext) {
        let id = session.id
        let descriptor = FetchDescriptor<AppInterval>(
            predicate: #Predicate { $0.sessionID == id }
        )
        let intervals = (try? context.fetch(descriptor)) ?? []

        // Keep the daily rollups consistent: subtract this block's contribution
        // before removing the interval rows it was derived from.
        let spans = intervals.map {
            AppSpan(bundleID: $0.appBundleID, appName: $0.appName, start: $0.start, duration: $0.duration)
        }
        let perApp = UsageAggregator.summarize(spans: spans, awaySeconds: 0, switchCount: 0).perApp
        Rollups.remove(
            day: session.start,
            activeSeconds: session.activeSeconds,
            awaySeconds: session.awaySeconds,
            perApp: perApp,
            in: context
        )

        for interval in intervals {
            context.delete(interval)
        }
        context.delete(session)
        try? context.save()
    }
}
