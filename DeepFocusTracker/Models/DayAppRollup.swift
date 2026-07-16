import Foundation
import SwiftData

/// Per-day, per-app active seconds. Powers the dashboard's top-apps chart without
/// scanning the `AppInterval` table. Maintained alongside `DayRollup`.
@Model
final class DayAppRollup {
    #Unique<DayAppRollup>([\.day, \.bundleID])
    #Index<DayAppRollup>([\.day])

    var day: Date
    var bundleID: String
    var appName: String
    var seconds: TimeInterval = 0

    init(day: Date, bundleID: String, appName: String, seconds: TimeInterval = 0) {
        self.day = day
        self.bundleID = bundleID
        self.appName = appName
        self.seconds = seconds
    }
}
