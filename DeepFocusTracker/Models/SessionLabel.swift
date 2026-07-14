import Foundation
import SwiftData

/// A reusable, colored label for focus blocks (e.g. "Writing", "Coding").
@Model
final class SessionLabel {
    @Attribute(.unique) var name: String
    var colorHex: String
    var createdAt: Date

    init(name: String, colorHex: String, createdAt: Date = .now) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}
