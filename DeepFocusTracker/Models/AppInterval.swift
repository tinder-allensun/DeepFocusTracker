import Foundation
import SwiftData

/// A contiguous span during a focus block where a single app was frontmost.
/// The app records these; it makes no judgment about whether an app is "focus"
/// or "distraction" — that interpretation is left to the user.
@Model
final class AppInterval {
    var sessionID: UUID
    var appBundleID: String
    var appName: String
    var start: Date
    var duration: TimeInterval

    init(sessionID: UUID, appBundleID: String, appName: String, start: Date, duration: TimeInterval) {
        self.sessionID = sessionID
        self.appBundleID = appBundleID
        self.appName = appName
        self.start = start
        self.duration = duration
    }
}
