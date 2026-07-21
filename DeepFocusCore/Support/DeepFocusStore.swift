import Foundation
import SwiftData

/// Builds the app's SwiftData store. It lives in the core module (not the app
/// entry point) so persistence detail stays out of `DeepFocusTrackerApp`, and so
/// the container is constructed one way for both the app and the tests' reference.
public enum DeepFocusStore {
    /// The container the app opens at launch: the on-disk store plus the dev-only
    /// synthetic-data seed (`SEED_TEST_DATA`, DEBUG only). Main-actor because the
    /// seed touches `mainContext`; the app calls it from its main-actor `init`.
    @MainActor
    public static func make() -> ModelContainer {
        let container = makeContainer()
        #if DEBUG
        TestDataSeeder.seedIfRequested(in: container.mainContext)
        #endif
        return container
    }

    /// Builds the local SwiftData store at an app-specific path so no other app
    /// can collide on SwiftData's generic default
    /// (`~/Library/Application Support/default.store`). If it can't be opened —
    /// e.g. after a schema change during development — the store is reset once
    /// and recreated. Replace the reset with a real migration plan before
    /// there's data worth preserving.
    static func makeContainer() -> ModelContainer {
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
    static func appStoreURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: "DeepFocusTracker", directoryHint: .isDirectory)
            .appending(path: "Focus.store")
    }
}
