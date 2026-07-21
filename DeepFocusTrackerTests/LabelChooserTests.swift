import Testing
import Foundation
@testable import DeepFocusCore

/// `LabelChooser` decides which reusable labels become menu-bar quick-pick chips
/// and in what order: recently-used first (most-recent → least), then never-used
/// seed defaults in a stable order, capped at `max`.
@MainActor
struct LabelChooserTests {

    private func label(_ name: String, created: Date, lastUsed: Date? = nil) -> SessionLabel {
        SessionLabel(name: name, colorHex: "#000000", createdAt: created, lastUsed: lastUsed)
    }

    @Test func usedLabelsPrecedeNeverUsedOnes() {
        let base = utcDate(2026, 1, 1)
        let labels = [
            label("Unused", created: base),
            label("Used", created: base, lastUsed: utcDate(2026, 1, 10)),
        ]
        #expect(LabelChooser.chips(from: labels).map(\.name) == ["Used", "Unused"])
    }

    @Test func usedLabelsAreOrderedMostRecentlyUsedFirst() {
        let base = utcDate(2026, 1, 1)
        let labels = [
            label("Older", created: base, lastUsed: utcDate(2026, 1, 5)),
            label("Newer", created: base, lastUsed: utcDate(2026, 1, 20)),
            label("Middle", created: base, lastUsed: utcDate(2026, 1, 12)),
        ]
        #expect(LabelChooser.chips(from: labels).map(\.name) == ["Newer", "Middle", "Older"])
    }

    @Test func unusedLabelsAreOrderedByCreationThenName() {
        let day1 = utcDate(2026, 1, 1)
        let day2 = utcDate(2026, 1, 2)
        let labels = [
            label("Zebra", created: day1),
            label("Apple", created: day1),  // same createdAt as Zebra → name breaks the tie
            label("Beta", created: day2),
        ]
        #expect(LabelChooser.chips(from: labels).map(\.name) == ["Apple", "Zebra", "Beta"])
    }

    @Test func capsAtMax() {
        let base = utcDate(2026, 1, 1)
        let labels = (1...10).map { label("L\($0)", created: base.addingTimeInterval(TimeInterval($0))) }
        #expect(LabelChooser.chips(from: labels, max: 5).count == 5)
        #expect(LabelChooser.chips(from: labels).count == 5)  // default max is 5
    }

    @Test func emptyInputGivesNoChips() {
        #expect(LabelChooser.chips(from: []).isEmpty)
    }
}
