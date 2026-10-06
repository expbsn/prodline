import Foundation
import SwiftData

/// A target that says "this worked": 1,000 visits, $200 revenue, 50 subscribers.
nonisolated struct SuccessCriterion: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var key: String
    var target: Double
}

/// The call at the end of the observe phase.
enum Verdict: String, CaseIterable, Identifiable {
    case keep, pivot, kill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: "Keep"
        case .pivot: "Pivot"
        case .kill: "Kill"
        }
    }

    var symbol: String {
        switch self {
        case .keep: "arrow.up.right.circle.fill"
        case .pivot: "arrow.triangle.branch"
        case .kill: "xmark.octagon.fill"
        }
    }

    var hex: Int {
        switch self {
        case .keep: 0x58CC02
        case .pivot: 0x1CB0F6
        case .kill: 0xFF4B4B
        }
    }

    var blurb: String {
        switch self {
        case .keep: "It's working. Keep watching the numbers for another stretch."
        case .pivot: "Something's there. Start a fresh build with what you learned."
        case .kill: "Not this one. Close it, keep the lessons, free up your time."
        }
    }

    /// The pill on cards once decided.
    var pastTense: String {
        switch self {
        case .keep: "Kept"
        case .pivot: "Pivoted"
        case .kill: "Killed"
        }
    }
}

enum VerdictEngine {
    static let xp = 25
    /// Keep: watch this many more days.
    static let keepDays = [14, 28, 56]

    struct Result: Identifiable {
        let criterion: SuccessCriterion
        let actual: Double
        var id: UUID { criterion.id }
        var progress: Double { criterion.target <= 0 ? 1 : min(1, max(0, actual / criterion.target)) }
        var hit: Bool { actual >= criterion.target }
    }

    /// Keys a target can use: the three main numbers plus whatever the project reports.
    static func availableKeys(_ project: Project, refresher: DataRefresher) -> [String] {
        let base = MetricKey.allCases.map(\.rawValue)
        let extras = refresher.extras(for: project).map(\.key).filter { $0 != "rating" && $0 != "ratings" }
        var seen = Set<String>()
        return (base + ["downloads", "mrr", "active_subscriptions", "sales"] + extras).filter { seen.insert($0).inserted }
    }

    static func title(_ key: String) -> String {
        MetricKey(rawValue: key)?.title ?? IntegrationMetric.title(key)
    }

    static func format(_ key: String, _ v: Double) -> String {
        key == MetricKey.revenue.rawValue ? MetricKey.money(v) : IntegrationMetric.format(key, v)
    }

    static func value(_ key: String, project: Project, refresher: DataRefresher) -> Double {
        if let k = MetricKey(rawValue: key) { return refresher.value(k, for: project) ?? 0 }
        return refresher.extras(for: project).first { $0.key == key }?.value ?? 0
    }

    static func results(_ project: Project, refresher: DataRefresher) -> [Result] {
        project.criteria.map { Result(criterion: $0, actual: value($0.key, project: project, refresher: refresher)) }
    }

    /// All targets hit: keep. Close, or one hit: pivot. Far off: kill. nil without targets.
    static func suggestion(_ results: [Result]) -> Verdict? {
        guard !results.isEmpty else { return nil }
        if results.allSatisfy(\.hit) { return .keep }
        let avg = results.map(\.progress).reduce(0, +) / Double(results.count)
        return results.contains(where: \.hit) || avg >= 0.4 ? .pivot : .kill
    }

    /// The observe phase is over and nothing has been decided since it ended.
    static func isDue(_ p: Project, now: Date = .now) -> Bool {
        guard p.phase(on: now) == .finished, p.verdict != .pivot, p.verdict != .kill else { return false }
        guard let at = p.verdictAt else { return true }
        return at < p.observeEnd.adding(days: -1)
    }

    /// Can be decided now: due, or early while observing.
    static func canDecide(_ p: Project, now: Date = .now) -> Bool {
        isDue(p, now: now) || (p.phase(on: now) == .observing && p.verdict != .pivot && p.verdict != .kill)
    }

    static func keep(_ p: Project, days: Int, profile: Profile, now: Date = .now) {
        p.verdictRaw = Verdict.keep.rawValue
        p.verdictAt = now
        // The new observe phase runs `days` from today, however late the call was made.
        p.observeDays = max(p.observeDays, Date.days(from: p.buildEnd, to: now) + days)
        profile.xp += xp
    }

    /// Closes this project and starts a fresh build that carries its look, repo and integrations over.
    @discardableResult
    static func pivot(_ p: Project, newName: String, note: String, profile: Profile, context: ModelContext, now: Date = .now) -> Project {
        p.verdictRaw = Verdict.pivot.rawValue
        p.verdictAt = now
        p.verdictNote = note
        let next = Project(name: newName, accentHex: p.accentHex, startDate: now, buildDays: profile.buildDays, observeDays: profile.observeDays)
        next.details = note.isEmpty ? p.details : note
        next.coverImage = p.coverImage
        next.githubRepo = p.githubRepo
        next.endpoint = p.endpoint
        next.criteria = p.criteria.map { SuccessCriterion(key: $0.key, target: $0.target) }
        next.integrations = p.integrations.map { old in
            var copy = old
            copy.id = UUID()
            if let secret = Keychain.get(old.keychainAccount) { Keychain.set(secret, for: copy.keychainAccount) }
            return copy
        }
        if let key = Keychain.get(p.id.uuidString) { Keychain.set(key, for: next.id.uuidString) }
        if let token = Keychain.get("gh-" + p.id.uuidString) { Keychain.set(token, for: "gh-" + next.id.uuidString) }
        ScheduleEngine.createProject(next, profile: profile, context: context)
        profile.xp += xp
        return next
    }

    static func kill(_ p: Project, lesson: String, profile: Profile, now: Date = .now) {
        p.verdictRaw = Verdict.kill.rawValue
        p.verdictAt = now
        p.verdictNote = lesson
        for m in p.milestones ?? [] where !m.isDone { Notifier.cancel(m) }
        profile.xp += xp
    }

    /// Back to undecided (e.g. a mistap), XP included. A pivot's new project stays.
    static func reopen(_ p: Project, profile: Profile) {
        guard p.verdict != nil else { return }
        p.verdictRaw = ""
        p.verdictAt = nil
        profile.xp = max(0, profile.xp - xp)
    }
}
