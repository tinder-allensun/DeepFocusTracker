import SwiftUI
import SwiftData
import AppKit
import DeepFocusCore

@main
struct DeepFocusTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var focus: FocusController
    /// Shared so the menu-bar popover can deep-link into the dashboard's stack.
    @State private var navigator = DashboardNavigator()

    init() {
        let container = DeepFocusStore.make()
        self.container = container
        _focus = State(initialValue: FocusController(context: container.mainContext))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(focus)
                .environment(navigator)
                .modelContainer(container)
        } label: {
            MenuBarLabel(focus: focus)
        }
        .menuBarExtraStyle(.window)

        Window("DeepFocusTracker — Dashboard", id: DashboardWindow.id) {
            DashboardView()
                .environment(navigator)
                .modelContainer(container)
        }
        .defaultSize(width: 700, height: 620)
        .windowResizability(.contentMinSize)
    }
}

/// Makes DeepFocusTracker a menu-bar-only agent (no Dock icon, no main menu).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
