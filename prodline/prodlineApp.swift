import SwiftUI
import SwiftData

@main
struct prodlineApp: App {
    let container: ModelContainer = {
        let schema = Schema([Profile.self, Project.self, Milestone.self, MetricSnapshot.self])
        // Unit tests get a throwaway in-memory store.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
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
