import SwiftUI
import SwiftData
import AppKit

@main
struct DeepFocusTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var focus: FocusController

    init() {
        let container = Self.makeContainer()
        self.container = container
        _focus = State(initialValue: FocusController(context: container.mainContext))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(focus)
                .modelContainer(container)
        } label: {
            MenuBarLabel(focus: focus)
        }
        .menuBarExtraStyle(.window)
    }

    /// Builds the local SwiftData store. If it can't be opened — e.g. after a
    /// schema change during development — the store is reset once and recreated.
    /// Replace with a real migration plan before there's data worth preserving.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            FocusSession.self,
            AppInterval.self,
            SessionLabel.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // 1) Try the on-disk store.
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }

        // 2) Couldn't open it — most likely a schema change during development.
        //    Reset the store once and retry. (Replace with a real migration plan
        //    before there's data worth preserving.)
        let base = configuration.url.path()
        for path in [base, base + "-wal", base + "-shm"] {
            try? FileManager.default.removeItem(atPath: path)
        }
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }

        // 3) Last resort: run in memory so the app still launches (no
        //    persistence this session) instead of hard-crashing.
        NSLog("DeepFocusTracker: on-disk store unavailable; falling back to an in-memory store.")
        let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: inMemory) {
            return container
        }
        fatalError("DeepFocusTracker could not create any model container.")
    }
}

/// Makes DeepFocusTracker a menu-bar-only agent (no Dock icon, no main menu).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
