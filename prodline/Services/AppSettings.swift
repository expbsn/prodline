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
        static let cheers = "config.cheers"
        /// "system", "light" or "dark".
        static let appearance = "config.appearance"
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
    /// Sample numbers for projects without an endpoint. Development only: release builds never invent numbers.
    #if DEBUG
    nonisolated static var sampleData: Bool { bool(Key.sampleData, true) }
    #else
    nonisolated static var sampleData: Bool { false }
    #endif
    nonisolated static var haptics: Bool { bool(Key.haptics, true) }
    /// Push notifications for goals, checkpoints and the streak when they happen with the app closed.
    nonisolated static var cheers: Bool { bool(Key.cheers, true) }
    /// Prodline's own relay (relay/ in the repo), used unless another address is set.
    nonisolated static let defaultRelayURL = "https://api.prodline.build"
    /// The relay for instant updates; "off" turns the feature off.
    nonisolated static var relayURL: URL? {
        var s = (UserDefaults.standard.string(forKey: Key.relayURL) ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = defaultRelayURL }
        if s.lowercased() == "off" { return nil }
        return URL(string: s.hasSuffix("/") ? String(s.dropLast()) : s)
    }
}
