import Foundation
import SwiftData

/// A reusable, colored label for focus blocks (e.g. "Writing", "Coding"). Powers
/// the menu-bar quick-pick chips; not linked to `FocusSession` (a session stores
/// its label as a plain string copy).
@Model
final class SessionLabel {
    @Attribute(.unique) var name: String
    var colorHex: String
    var createdAt: Date
    /// When this label was last used to start a block; `nil` until first used.
    /// Drives the chooser's most-recently-used ordering. Optional so migrating an
    /// existing store needs no default (a non-optional new attribute would).
    var lastUsed: Date?

    init(name: String, colorHex: String, createdAt: Date = .now, lastUsed: Date? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }
}
