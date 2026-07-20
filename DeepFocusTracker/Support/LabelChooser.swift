import Foundation

/// Orders the reusable labels for the menu-bar quick-pick chooser.
///
/// Recently-used labels come first (most-recent → least), then never-used labels
/// (the untouched seed defaults) in a stable order, capped at `max`. Pure and
/// deterministic given its input, so it can be reasoned about / unit-tested apart
/// from the view.
enum LabelChooser {
    static func chips(from labels: [SessionLabel], max: Int = 5) -> [SessionLabel] {
        let used = labels
            .filter { $0.lastUsed != nil }
            .sorted { $0.lastUsed! > $1.lastUsed! }
        // Never used yet (seed defaults): stable order by creation, then name — the
        // name tiebreak keeps the trailing chips from reordering when seeds share a
        // creation timestamp (they're inserted in a tight loop).
        let unused = labels
            .filter { $0.lastUsed == nil }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.name < rhs.name
            }
        return Array((used + unused).prefix(max))
    }
}
