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
        for interval in (try? context.fetch(descriptor)) ?? [] {
            context.delete(interval)
        }
        context.delete(session)
        try? context.save()
    }
}
