import SwiftUI
import SwiftData
import AppKit

@main
struct DeepFocusTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Optional so the app can run as a bare host under test (see `init`).
    private let container: ModelContainer?
    @State private var focus: FocusController?
    /// Shared so the menu-bar popover can deep-link into the dashboard's stack.
    @State private var navigator = DashboardNavigator()

    init() {
        // When launched only to host the unit-test bundle, don't stand up SwiftData
        // at all: the tests create their own `ModelContainer`, and a second
        // container over the same `@Model` types in one process makes CoreData trap
        // ("multiple NSEntityDescriptions claim the NSManagedObject subclass"). So
        // run a bare host. `DFT_TESTING` is set by the scheme's Test action.
        guard ProcessInfo.processInfo.environment["DFT_TESTING"] == nil else {
            self.container = nil
            return
        }

        let container = Self.makeContainer()
        self.container = container
        #if DEBUG
        TestDataSeeder.seedIfRequested(in: container.mainContext)
        #endif
        _focus = State(initialValue: FocusController(context: container.mainContext))
    }

    var body: some Scene {
        // The scene structure is unconditional (`SceneBuilder` doesn't allow
        // control flow); the nil-under-test cases are handled *inside* the view
        // builders, which do. In the real app `focus`/`container` are set; while
        // hosting tests they're nil and these render a bare host (see `init`).
        MenuBarExtra {
            if let focus, let container {
                MenuBarView()
                    .environment(focus)
                    .environment(navigator)
                    .modelContainer(container)
            }
        } label: {
            if let focus {
                MenuBarLabel(focus: focus)
            } else {
                Image(systemName: "brain")
            }
        }
        .menuBarExtraStyle(.window)

        Window("DeepFocusTracker — Dashboard", id: DashboardWindow.id) {
            if let container {
                DashboardView()
                    .environment(navigator)
                    .modelContainer(container)
            }
        }
        .defaultSize(width: 700, height: 620)
        .windowResizability(.contentMinSize)
    }

    /// Builds the local SwiftData store at an app-specific path so no other app
    /// can collide on SwiftData's generic default
    /// (`~/Library/Application Support/default.store`). If it can't be opened —
    /// e.g. after a schema change during development — the store is reset once
    /// and recreated. Replace the reset with a real migration plan before
    /// there's data worth preserving.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            FocusSession.self,
            AppInterval.self,
            SessionLabel.self,
            DayRollup.self,
            DayAppRollup.self,
        ])

        let storeURL = appStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        // 1) Try the on-disk store.
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }

        // 2) Couldn't open it — most likely a schema change during development.
        //    Reset the store once and retry. (Replace with a real migration plan
        //    before there's data worth preserving.)
        let base = storeURL.path()
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

    /// App-specific store location:
    /// `~/Library/Application Support/DeepFocusTracker/Focus.store`.
    private static func appStoreURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: "DeepFocusTracker", directoryHint: .isDirectory)
            .appending(path: "Focus.store")
    }
}

/// Makes DeepFocusTracker a menu-bar-only agent (no Dock icon, no main menu).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
