import SwiftUI
import SwiftData

@main
struct prodlineApp: App {
    let container: ModelContainer = {
        let schema = Schema([Profile.self, Project.self, Milestone.self, MetricSnapshot.self, Goal.self, Idea.self])
        // Unit tests get a throwaway in-memory store.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
        moveStoreIntoAppGroup()
        do {
            // Private CloudKit database (container from the entitlements) keeps devices in sync.
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            // No iCloud available (e.g. unsigned simulator): stay local rather than crash.
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do { return try ModelContainer(for: schema, configurations: [local]) }
            catch { fatalError("Could not create ModelContainer: \(error)") }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.ink)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(DataRefresher.backgroundTaskID)) {
            await DataRefresher.runBackground(container: container)
        }
    }
}

/// With the App Group (for widgets), SwiftData keeps its default store in the group container instead of
/// the app's own Application Support. Carry an existing store over once, so updating never starts empty
/// (on devices without iCloud nothing else would bring the data back).
private func moveStoreIntoAppGroup() {
    let fm = FileManager.default
    guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)?
            .appendingPathComponent("Library/Application Support", isDirectory: true),
          let old = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let oldStore = old.appendingPathComponent("default.store")
    let newStore = group.appendingPathComponent("default.store")
    guard fm.fileExists(atPath: oldStore.path), !fm.fileExists(atPath: newStore.path) else { return }
    try? fm.createDirectory(at: group, withIntermediateDirectories: true)
    for suffix in ["", "-wal", "-shm"] {
        let from = old.appendingPathComponent("default.store" + suffix)
        if fm.fileExists(atPath: from.path) {
            try? fm.copyItem(at: from, to: group.appendingPathComponent("default.store" + suffix))
        }
    }
    // Externally stored attributes (cover photos) live next to the store.
    let support = old.appendingPathComponent(".default_SUPPORT")
    if fm.fileExists(atPath: support.path) {
        try? fm.copyItem(at: support, to: group.appendingPathComponent(".default_SUPPORT"))
    }
}
