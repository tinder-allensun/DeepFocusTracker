import SwiftUI
import SwiftData
import AppKit

@main
struct DeepFocusTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var focus: FocusController

    init() {
        let schema = Schema([
            FocusSession.self,
            AppInterval.self,
            AppCategoryRule.self,
            SessionLabel.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            self.container = container
            _focus = State(initialValue: FocusController(context: container.mainContext))
        } catch {
            fatalError("Failed to create the DeepFocusTracker model container: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(focus)
                .modelContainer(container)
        } label: {
            Image(systemName: "brain.head.profile")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Makes DeepFocusTracker a menu-bar-only agent (no Dock icon, no main menu).
/// Set both here at runtime and via `LSUIElement` in the Info.plist so the
/// behavior holds regardless of how the app is launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
