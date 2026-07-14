import Foundation
import SwiftData

/// A contiguous span during a focus block where a single app was frontmost.
/// Written by the activity tracker (M2); defined now so the schema is stable.
@Model
final class AppInterval {
    var sessionID: UUID
    var appBundleID: String
    var appName: String
    var categoryRaw: String
    var start: Date
    var duration: TimeInterval

    init(
        sessionID: UUID,
        appBundleID: String,
        appName: String,
        category: FocusCategory,
        start: Date,
        duration: TimeInterval
    ) {
        self.sessionID = sessionID
        self.appBundleID = appBundleID
        self.appName = appName
        self.categoryRaw = category.rawValue
        self.start = start
        self.duration = duration
    }

    var category: FocusCategory {
        get { FocusCategory(rawValue: categoryRaw) ?? .neutral }
        set { categoryRaw = newValue.rawValue }
    }
}
