import Foundation
import SwiftData
import SwiftUI
import UIKit

// All properties have defaults and relationships are optional so the schema is CloudKit-compatible.

@Model
final class Profile {
    var createdAt: Date = Date.now
    var onboarded: Bool = false
    var xp: Int = 0
    /// Consecutive days with progress (see Streak).
    var streak: Int = 0
    /// The last day that counted toward the streak; the flame is lit when that's today.
    var streakActiveToday: Date? = nil
    var bestStreak: Int = 0
    var completedOnTime: Int = 0
    var completedLate: Int = 0

    // Custom building scheme
    var buildDays: Int = 14
    var observeDays: Int = 28
    var newProjectEveryDays: Int = 14
    /// Bit (weekday - 1) set => checkpoint on that weekday (Calendar weekday, Sunday = 1).
    var milestoneWeekdayMask: Int = 34 // Mon + Fri
    var reminderHour: Int = 9
    /// The "still time today" and streak nudge hour.
    var nudgeHour: Int = 18
    /// WorkStyle raw value; empty until picked.
    var workStyleRaw: String = ""
    var remindersEnabled: Bool = true
    /// Projects allowed in the build phase at once (upcoming ones count too); 0 = no limit.
    var buildLimit: Int = 2
    /// What counts as a win (SuccessFocus raw value) and the target for it; new projects start with it.
    var successFocusRaw: String = ""
    var successTarget: Double = 0

    init() {}

    var level: Int { xp / 100 + 1 }
    var levelProgress: Double { Double(xp % 100) / 100 }
    var onTimeRate: Double? {
        let total = completedOnTime + completedLate
        return total == 0 ? nil : Double(completedOnTime) / Double(total)
    }

    func hasWeekday(_ weekday: Int) -> Bool { milestoneWeekdayMask & (1 << (weekday - 1)) != 0 }
    func toggleWeekday(_ weekday: Int) { milestoneWeekdayMask ^= (1 << (weekday - 1)) }
}

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    /// Short pitch shown on the project screen.
    var details: String = ""
    var accentHex: Int = 0x58CC02
    /// Square JPEG cover. Its dominant color usually becomes the accent.
    @Attribute(.externalStorage) var coverImage: Data? = nil
    var startDate: Date = Date.now.startOfDay
    var buildDays: Int = 14
    var observeDays: Int = 28
    /// Metrics endpoint. Empty => sample data. The API key lives in the Keychain.
    var endpoint: String = ""
    /// Linked GitHub repository as "owner/name". An optional token lives in the Keychain.
    var githubRepo: String = ""
    var lastCommitAt: Date? = nil
    /// The linked repo has a prodline.json: checkpoints and goals mirror the file exactly, nothing else.
    var followsPlanFile: Bool = false
    /// Commits per local day ("yyyy-MM-dd" → count) since the start date, from the linked repo.
    var commitDaysData: Data? = nil
    /// What success looks like (1–3 targets), judged when the observe phase ends.
    var criteriaData: Data? = nil
    /// "keep", "pivot" or "kill" once decided; a keep extends the observe phase and asks again at its end.
    var verdictRaw: String = ""
    var verdictAt: Date? = nil
    /// What changes (pivot) or what was learned (kill).
    var verdictNote: String = ""
    /// Connected services (App Store Connect, RevenueCat, Plausible…), without their keys (those are in the Keychain).
    var integrationsData: Data? = nil
    /// The numbers picked for the Traction tiles (comma-separated keys), when there are more than three.
    var trackedMetricsRaw: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Milestone.project)
    var milestones: [Milestone]? = []
    @Relationship(deleteRule: .cascade, inverse: \MetricSnapshot.project)
    var snapshots: [MetricSnapshot]? = []

    init(name: String, accentHex: Int, startDate: Date, buildDays: Int, observeDays: Int) {
        self.name = name
        self.accentHex = accentHex
        self.startDate = startDate.startOfDay
        self.buildDays = buildDays
        self.observeDays = observeDays
    }

    var accent: Accent { Accent(hex: accentHex) }
    var initial: String { name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }
    var cover: UIImage? { CoverCache.image(coverImage, key: id.uuidString) }

    var criteria: [SuccessCriterion] {
        get { criteriaData.flatMap { try? JSONDecoder().decode([SuccessCriterion].self, from: $0) } ?? [] }
        set { criteriaData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var verdict: Verdict? { Verdict(rawValue: verdictRaw) }

    var integrations: [Integration] {
        get { integrationsData.flatMap { try? JSONDecoder().decode([Integration].self, from: $0) } ?? [] }
        set { integrationsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var commitDays: [String: Int] {
        get { commitDaysData.flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:] }
        set { commitDaysData = try? JSONEncoder().encode(newValue) }
    }

    var buildEnd: Date { startDate.adding(days: buildDays) }
    var observeEnd: Date { buildEnd.adding(days: observeDays) }
    var launchDay: Date { buildEnd.adding(days: -1) }

    func phase(on date: Date = .now) -> Phase {
        let d = date.startOfDay
        if d < startDate { return .upcoming }
        if d < buildEnd { return .building }
        if d < observeEnd { return .observing }
        return .finished
    }

    var isActive: Bool { phase() == .building || phase() == .observing }

    /// 1-based day within the current phase.
    var dayInPhase: Int {
        switch phase() {
        case .upcoming: 0
        case .building: Date.days(from: startDate, to: .now) + 1
        case .observing: Date.days(from: buildEnd, to: .now) + 1
        case .finished: observeDays
        }
    }

    var phaseLength: Int { phase() == .observing ? observeDays : buildDays }

    /// 0...1 across build + observe.
    var overallProgress: Double {
        let total = Double(buildDays + observeDays)
        let done = Double(Date.days(from: startDate, to: .now))
        return min(max(done / total, 0), 1)
    }

    var daysLeftInPhase: Int {
        switch phase() {
        case .upcoming: Date.days(from: .now, to: startDate)
        case .building: Date.days(from: .now, to: buildEnd)
        case .observing: Date.days(from: .now, to: observeEnd)
        case .finished: 0
        }
    }

    var sortedMilestones: [Milestone] { (milestones ?? []).sorted { $0.dueDate < $1.dueDate } }
    var nextMilestone: Milestone? { sortedMilestones.first { !$0.isDone } }
    var sortedSnapshots: [MetricSnapshot] { (snapshots ?? []).sorted { $0.date < $1.date } }
    var latestSnapshot: MetricSnapshot? { (snapshots ?? []).max { $0.date < $1.date } }

    /// Numbers come from somewhere real: an endpoint or at least one integration.
    var hasDataSource: Bool { hasEndpoint || !integrations.isEmpty }

    var hasEndpoint: Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else { return false }
        return url.scheme?.hasPrefix("http") == true && url.host() != nil
    }
}

@Model
final class Milestone {
    var id: UUID = UUID()
    var title: String = ""
    var dueDate: Date = Date.now.startOfDay
    var completedAt: Date? = nil
    var missed: Bool = false
    var isLaunch: Bool = false
    /// Renamed by the user; repo-provided names (prodline.json) no longer overwrite it.
    var titleIsCustom: Bool = false
    /// XP paid when it was completed, and whether it counted as on time; undoing gives exactly this back.
    var xpEarned: Int = 0
    var countedOnTime: Bool = false
    var project: Project? = nil
    @Relationship(deleteRule: .cascade, inverse: \Goal.milestone)
    var goals: [Goal]? = []

    init(title: String, dueDate: Date, isLaunch: Bool = false) {
        self.title = title
        self.dueDate = dueDate.startOfDay
        self.isLaunch = isLaunch
    }

    var isDone: Bool { completedAt != nil }
    func isOverdue(on now: Date = .now) -> Bool { !isDone && dueDate < now.startOfDay }
    var isOverdue: Bool { isOverdue() }
    var isDueToday: Bool { !isDone && dueDate == Date.now.startOfDay }
    var completedOnTime: Bool { completedAt.map { $0.startOfDay <= dueDate } ?? false }

    var sortedGoals: [Goal] { (goals ?? []).sorted { ($0.order, $0.title) < ($1.order, $1.title) } }
    var openGoals: [Goal] { sortedGoals.filter { !$0.isDone } }
    /// How lists show them: open goals on top, done ones below, each in their usual order.
    var displayGoals: [Goal] { openGoals + sortedGoals.filter(\.isDone) }
    var hasGoals: Bool { !(goals ?? []).isEmpty }
}

enum GoalSource: String, CaseIterable {
    case api, github, repoFile, ai, metric, manual

    var label: String {
        switch self {
        case .api: "From your API"
        case .github: "From GitHub"
        case .repoFile: "From prodline.json"
        case .ai: "Suggested"
        case .metric: "Traction target"
        case .manual: "Added by you"
        }
    }

    /// For the "Goals from …" line.
    var shortName: String {
        switch self {
        case .api: "your API"
        case .github: "GitHub"
        case .repoFile: "prodline.json"
        case .ai: "suggestions"
        case .metric: "targets"
        case .manual: "you"
        }
    }

    var symbol: String {
        switch self {
        case .api: "bolt.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .repoFile: "doc.text"
        case .ai: "sparkles"
        case .metric: "chart.line.uptrend.xyaxis"
        case .manual: "pencil"
        }
    }

    /// Remote and metric goals complete themselves; the user can't tick them.
    var isAutomatic: Bool { self == .api || self == .github || self == .repoFile || self == .metric }
}

/// A concrete deliverable inside a checkpoint. A checkpoint with goals completes once all are done.
@Model
final class Goal {
    var id: UUID = UUID()
    /// Stable key for synced goals: "api:<id>", "gh:<issue>", "metric:<key>". Empty for local goals.
    var externalID: String = ""
    var sourceRaw: String = GoalSource.manual.rawValue
    var title: String = ""
    var detail: String = ""
    var url: String = ""
    var metricKey: String? = nil
    var target: Double? = nil
    var isDone: Bool = false
    var doneAt: Date? = nil
    var order: Int = 0
    /// XP for finishing this goal was handed out (or it arrived already done, which earns none).
    var xpAwarded: Bool = false
    /// What it actually paid; unticking takes this back and lets a later tick pay again.
    var xpPaid: Int = 0
    var milestone: Milestone? = nil

    init(title: String, source: GoalSource, externalID: String = "", order: Int = 0) {
        self.title = title
        self.sourceRaw = source.rawValue
        self.externalID = externalID
        self.order = order
    }

    var source: GoalSource { GoalSource(rawValue: sourceRaw) ?? .manual }

    func setDone(_ done: Bool, at date: Date = .now) {
        guard done != isDone else { return }
        isDone = done
        doneAt = done ? date : nil
    }
}

@Model
final class MetricSnapshot {
    var date: Date = Date.now
    var visits: Double = 0
    var socialViews: Double = 0
    var revenue: Double = 0
    /// Any non-standard metrics the endpoint reports (e.g. "signups").
    var extras: [String: Double] = [:]
    var project: Project? = nil

    init(date: Date, visits: Double, socialViews: Double, revenue: Double, extras: [String: Double] = [:]) {
        self.date = date
        self.visits = visits
        self.socialViews = socialViews
        self.revenue = revenue
        self.extras = extras
    }

    func value(_ key: MetricKey) -> Double {
        switch key {
        case .visits: visits
        case .socialViews: socialViews
        case .revenue: revenue
        }
    }
}

/// Something to build later. Parked here instead of starting a project while the build slots are full.
@Model
final class Idea {
    var id: UUID = UUID()
    var title: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    /// Turned into a project; kept so the inbox can show what came of it.
    var startedAt: Date? = nil
    var projectID: UUID? = nil

    init(title: String, note: String = "") {
        self.title = title
        self.note = note
    }
}
