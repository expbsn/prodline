import Foundation
import SwiftData
import UIKit

/// Instant updates through the relay (relay/ in the repo): GitHub calls it on every push, and it sends a
/// silent push here, so goals, ticks and the streak refresh right away, even while the app is closed.
///
/// No accounts. This device registers with a random ID and a secret that stays on it. Each project gets a
/// hook (ID + secret) that the user adds as a webhook to the repo; the hook syncs through iCloud Keychain,
/// so their other devices can follow the same hook.
enum Relay {
    /// Posted with the hook ID when a push arrives while the app is open.
    static let pushed = Notification.Name("Relay.pushed")

    static var isEnabled: Bool { AppSettings.relayURL != nil }

    // MARK: Identity

    private static let deviceKey = "relay.device"
    private static let tokenKey = "relay.token"
    private static let secretAccount = "relay-device-secret"

    static func randomID(_ prefix: String) -> String {
        prefix + "_" + (0..<24).map { _ in String("abcdefghijklmnopqrstuvwxyz0123456789".randomElement()!) }.joined()
    }

    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = randomID("dev")
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    /// Stays on this device (not in iCloud Keychain): it proves this device is the one registered.
    static var deviceSecret: String {
        if let s = Keychain.get(secretAccount) { return s }
        let s = randomID("ds")
        Keychain.set(s, for: secretAccount, synced: false)
        return s
    }

    struct Hook: Equatable { let id: String; let secret: String }

    private static func hookAccount(_ p: Project) -> String { "relay-hook-" + p.id.uuidString }

    /// The project's hook, made on first use. Synced through iCloud Keychain like other secrets.
    static func hook(for p: Project) -> Hook {
        if let s = Keychain.get(hookAccount(p)), case let parts = s.split(separator: " "), parts.count == 2 {
            return Hook(id: String(parts[0]), secret: String(parts[1]))
        }
        let h = Hook(id: randomID("hk"), secret: randomID("hs"))
        Keychain.set(h.id + " " + h.secret, for: hookAccount(p))
        return h
    }

    static func webhookURL(_ hook: Hook) -> URL? {
        AppSettings.relayURL?.appendingPathComponent("github").appendingPathComponent(hook.id)
    }

    static func project(forHook id: String, in projects: [Project]) -> Project? {
        projects.first { !$0.githubRepo.isEmpty && Keychain.get(hookAccount($0))?.hasPrefix(id + " ") == true }
    }

    // MARK: Registration

    /// The APNs token arrived: register this device, then follow every project's hook.
    static func register(token: Data, projects: [Project]) async {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        guard await registerDevice(hex) else { return }
        // The push-to-start token may have arrived before the device was known to the relay.
        await sendStartToken()
        for p in projects where !p.githubRepo.isEmpty { await follow(p) }
    }

    static let startTokenKey = "relay.startToken"

    static func sendStartToken() async {
        guard let hex = UserDefaults.standard.string(forKey: startTokenKey) else { return }
        _ = await post("devices/\(deviceID)/start-token", ["deviceSecret": deviceSecret, "startToken": hex])
    }

    @discardableResult
    private static func registerDevice(_ token: String) async -> Bool {
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        return await post("devices", ["device": deviceID, "secret": deviceSecret, "token": token, "env": env])
    }

    /// Follow a project's hook from this device (also creates the hook on the relay).
    @discardableResult
    static func follow(_ p: Project) async -> Bool {
        guard isEnabled, UserDefaults.standard.string(forKey: tokenKey) != nil else { return false }
        let h = hook(for: p)
        return await post("hooks/" + h.id, ["secret": h.secret, "device": deviceID, "deviceSecret": deviceSecret])
    }

    static func post(_ path: String, _ body: [String: String]) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        return await send(path, method: "POST", data: data)
    }

    static func send(_ path: String, method: String, data: Data) async -> Bool {
        guard let base = AppSettings.relayURL else { return false }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        guard let (_, res) = try? await URLSession.shared.data(for: req) else { return false }
        return (res as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: Pushes

    /// A silent push while the app isn't on screen: sync that project's repo and save.
    @MainActor
    static func handleInBackground(hookID: String, container: ModelContainer) async -> Bool {
        let context = ModelContext(container)
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard let p = project(forHook: hookID, in: projects) else { return false }
        let github = GitHubService()
        let changed = await github.refresh(projects: [p], force: true)
        guard !changed.isEmpty, let snap = github.snapshots[p.id] else { return false }
        GoalEngine.syncGitHub(snap, project: p, context: context)
        if let profile = try? context.fetch(FetchDescriptor<Profile>()).first, profile.onboarded {
            // XP, checkpoints and the streak, as on screen; Cheer turns the wins into notifications.
            let refresher = DataRefresher()
            GoalEngine.afterRefresh(projects: projects, profile: profile, refresher: refresher, celebration: nil, context: context)
            StreakNudge.schedule(profile)
            WidgetPublisher.publish(projects: projects, profile: profile, refresher: refresher)
        }
        try? context.save()
        return true
    }
}
