import SwiftUI
import SwiftData
import UserNotifications

/// Notification taps: ones that carry a prodline:// link (the weekly review) open it.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Instant updates: the relay needs this device's push token.
        if Relay.isEnabled { application.registerForRemoteNotifications() }
        #if DEBUG
        // -PRODLINE_RELAY_TOKEN <hex>: pretend APNs handed out this token (simulators often get none).
        if let hex = UserDefaults.standard.string(forKey: "PRODLINE_RELAY_TOKEN"), Relay.isEnabled {
            let bytes = stride(from: 0, to: hex.count - 1, by: 2).compactMap { i -> UInt8? in
                let s = hex.index(hex.startIndex, offsetBy: i)
                return UInt8(hex[s...hex.index(after: s)], radix: 16)
            }
            self.application(application, didRegisterForRemoteNotificationsWithDeviceToken: Data(bytes))
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Relay: no push token (\(error.localizedDescription))")
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            let context = ModelContext(prodlineApp.sharedContainer)
            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            await Relay.register(token: deviceToken, projects: projects)
        }
    }

    /// A silent push from the relay: a repo changed. Open: the running sync picks it up. Closed or in the
    /// background: sync that project here, within the few seconds iOS allows.
    @MainActor
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let info = userInfo["prodline"] as? [String: Any], let hook = info["hook"] as? String else { return .noData }
        GitHubService.trace("relay push for \(hook), app \(application.applicationState == .active ? "open" : "in background")")
        if application.applicationState == .active {
            NotificationCenter.default.post(name: Relay.pushed, object: hook)
            return .newData
        }
        return await Relay.handleInBackground(hookID: hook, container: prodlineApp.sharedContainer) ? .newData : .noData
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String, link == "prodline://review" else { return }
        // The UI may still be starting; give it a moment before asking it to open.
        try? await Task.sleep(for: .milliseconds(600))
        await MainActor.run { NotificationCenter.default.post(name: WeeklyReview.open, object: nil) }
    }

    /// While the app is open, deadline reminders stay quiet (the app shows its own nudges).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == WeeklyReview.notificationID ? [.banner] : []
    }
}

@main
struct prodlineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var container: ModelContainer { Self.sharedContainer }

    /// One store for the app and for background work started by pushes.
    static let sharedContainer: ModelContainer = {
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
