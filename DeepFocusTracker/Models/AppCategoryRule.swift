import Foundation
import SwiftData

/// A classification of an application as focus / neutral / distraction. Seeded
/// with sensible defaults and editable by the user; remembered globally.
@Model
final class AppCategoryRule {
    @Attribute(.unique) var appBundleID: String
    var appName: String
    var categoryRaw: String

    init(appBundleID: String, appName: String, category: FocusCategory) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.categoryRaw = category.rawValue
    }

    var category: FocusCategory {
        get { FocusCategory(rawValue: categoryRaw) ?? .neutral }
        set { categoryRaw = newValue.rawValue }
    }
}
