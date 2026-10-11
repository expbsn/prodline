import Foundation

/// User-tunable behavior (Me → Configuration). Stored in UserDefaults; read where the behavior happens.
enum AppSettings {
    enum Key {
        static let refreshSeconds = "config.refreshSeconds"
        static let githubMinutes = "config.githubMinutes"
        static let commitWatch = "config.commitWatch"
        static let suggestions = "config.suggestions"
        static let sampleData = "config.sampleData"
        static let haptics = "config.haptics"
        static let relayURL = "config.relayURL"
    }

    nonisolated private static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    nonisolated private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    /// Foreground metrics polling.
    nonisolated static var refreshSeconds: Int { max(10, int(Key.refreshSeconds, 30)) }
    /// Full GitHub sync (issues, README, prodline.json).
    nonisolated static var githubMinutes: Int { max(1, int(Key.githubMinutes, 10)) }
    /// Cheap conditional check for new commits between full syncs.
    nonisolated static var commitWatch: Bool { bool(Key.commitWatch, true) }
    /// On-device goal suggestions.
    nonisolated static var suggestions: Bool { bool(Key.suggestions, true) }
    /// Sample numbers for projects without an endpoint.
    nonisolated static var sampleData: Bool { bool(Key.sampleData, true) }
    nonisolated static var haptics: Bool { bool(Key.haptics, true) }
    /// Prodline's own relay (relay/ in the repo), used unless another address is set.
    nonisolated static let defaultRelayURL = "https://prodline-relay.prodline-relay.workers.dev"
    /// The relay for instant updates; "off" turns the feature off.
    nonisolated static var relayURL: URL? {
        var s = (UserDefaults.standard.string(forKey: Key.relayURL) ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = defaultRelayURL }
        if s.lowercased() == "off" { return nil }
        return URL(string: s.hasSuffix("/") ? String(s.dropLast()) : s)
    }
}
