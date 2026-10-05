import Foundation
import SwiftData

/// Keeps checkpoint goals in sync with their sources and completes checkpoints whose goals are all done.
///
/// Priority: goals from the project's API or GitHub replace AI suggestions on the same checkpoint.
/// Without any source (or on-device AI), checkpoints stay plain and are completed by hand.
enum GoalEngine {
    /// A goal coming from a remote source, normalized.
    struct Incoming {
        var externalID: String
        var title: String
        var detail: String = ""
        var url: String = ""
        var checkpoint: Int?
        var due: Date?
        var done: Bool
        var metricKey: String?
        var target: Double?
    }

    // MARK: Placement

    /// Where a goal lands: explicit position, else first deadline on/after its due date, else the next open one.
    static func milestone(checkpoint: Int?, due: Date?, in project: Project) -> Milestone? {
        let ms = project.sortedMilestones
        return slot(checkpoint: checkpoint, due: due, dues: ms.map(\.dueDate), done: ms.map(\.isDone)).map { ms[$0] }
    }

    /// Placement rule shared by real checkpoints and the create-flow preview:
    /// explicit position, else the first deadline on or after the due date, else the next open one.
    static func slot(checkpoint: Int?, due: Date?, dues: [Date], done: [Bool]? = nil) -> Int? {
        guard !dues.isEmpty else { return nil }
        if let n = checkpoint, (1...dues.count).contains(n) { return n - 1 }
        if let due { return dues.firstIndex { $0 >= due.startOfDay } ?? dues.count - 1 }
        return done.flatMap { $0.firstIndex(of: false) } ?? 0
    }

    /// What a linked repo will put on each deadline, for showing before the project exists.
    struct RepoPreview {
        var goals: [[(title: String, source: GoalSource)]]
        var names: [String?]
        /// prodline.json is the plan: no AI suggestions on top of it.
        var hasPlanFile: Bool
        var isEmpty: Bool { goals.allSatisfy(\.isEmpty) && names.allSatisfy { $0 == nil } }
    }

    static func repoPreview(_ snap: GitHubSnapshot, dues: [Date]) -> RepoPreview {
        var goals = Array(repeating: [(title: String, source: GoalSource)](), count: dues.count)
        var names = Array(repeating: String?.none, count: dues.count)
        for item in githubIncoming(snap) {
            if let i = slot(checkpoint: item.checkpoint, due: item.due, dues: dues), !item.done { goals[i].append((item.title, .github)) }
        }
        for g in snap.planFile?.goals ?? [] where !(g.done ?? false) {
            if let i = slot(checkpoint: g.checkpoint, due: g.due, dues: dues) { goals[i].append((g.title, .repoFile)) }
        }
        for c in snap.planFile?.checkpoints ?? [] {
            if let i = slot(checkpoint: c.checkpoint, due: c.due, dues: dues) { names[i] = c.title }
        }
        return RepoPreview(goals: goals, names: names, hasPlanFile: snap.planFile != nil)
    }

    // MARK: Remote sync

    static func syncAPI(_ goals: [MetricsPayload.RemoteGoal], project: Project, context: ModelContext) {
        let incoming = goals.map {
            Incoming(externalID: "api:\($0.id)", title: $0.title, detail: $0.detail ?? "", url: $0.url ?? "",
                     checkpoint: $0.checkpoint, due: $0.due, done: $0.done ?? false,
                     metricKey: $0.metric?.key, target: $0.metric?.target)
        }
        sync(incoming, prefix: "api:", source: .api, project: project, context: context)
    }

    /// GitHub issues become goals when they belong to a GitHub milestone or carry the `prodline` label.
    /// A milestone's due date picks the checkpoint; without one, the Nth milestone maps to the Nth checkpoint.
    static func syncGitHub(_ snap: GitHubSnapshot, project: Project, context: ModelContext) {
        sync(githubIncoming(snap), prefix: "gh:", source: .github, project: project, context: context)

        // prodline.json: same shape as API goals. A missing file clears its open goals; a broken one keeps them.
        if let plan = snap.planFile {
            // Checkpoints first, so goals can land on ones the file just added.
            nameCheckpoints(plan.checkpoints ?? [], project: project, context: context)
            syncPlanFile(plan.goals, project: project, context: context)
            // The repo's plan is the source of truth: drop open suggestions everywhere, not just where it placed goals.
            for m in project.sortedMilestones {
                for g in m.goals ?? [] where g.source == .ai && !g.isDone { context.delete(g) }
            }
        } else if snap.planFileError == nil {
            syncPlanFile([], project: project, context: context)
        }
    }

    private static func githubIncoming(_ snap: GitHubSnapshot) -> [Incoming] {
        let ordered = snap.milestones.sorted { $0.number < $1.number }
        return snap.issues.filter(\.isPlanned).map { issue in
            var checkpoint: Int?, due: Date?
            if let ref = issue.milestone, let m = ordered.first(where: { $0.number == ref.number }) {
                if let d = m.due_on { due = d } else { checkpoint = (ordered.firstIndex(of: m) ?? 0) + 1 }
            }
            return Incoming(externalID: "gh:\(issue.number)", title: issue.title, url: issue.html_url,
                            checkpoint: checkpoint, due: due, done: issue.isClosed)
        }
    }

    /// Checkpoints from prodline.json. A dated entry names the checkpoint on that day, or adds one if
    /// there is none; a positional entry names the Nth deadline. Names the user set themselves win.
    static func nameCheckpoints(_ entries: [GitHubSnapshot.PlanFile.Checkpoint], project: Project, context: ModelContext) {
        for c in entries {
            let title = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if c.checkpoint == nil, let due = c.due?.startOfDay {
                if let m = project.sortedMilestones.first(where: { $0.dueDate == due }) {
                    if !m.titleIsCustom { m.title = title }
                } else {
                    let m = Milestone(title: title, dueDate: due)
                    context.insert(m)
                    m.project = project
                }
            } else if let m = milestone(checkpoint: c.checkpoint, due: c.due, in: project), !m.titleIsCustom {
                m.title = title
            }
        }
        ScheduleEngine.renumber(project)
    }

    static func syncPlanFile(_ goals: [MetricsPayload.RemoteGoal], project: Project, context: ModelContext) {
        let incoming = goals.map {
            Incoming(externalID: "file:\($0.id)", title: $0.title, detail: $0.detail ?? "", url: $0.url ?? "",
                     checkpoint: $0.checkpoint, due: $0.due, done: $0.done ?? false,
                     metricKey: $0.metric?.key, target: $0.metric?.target)
        }
        sync(incoming, prefix: "file:", source: .repoFile, project: project, context: context)
    }

    static func sync(_ incoming: [Incoming], prefix: String, source: GoalSource, project: Project, context: ModelContext) {
        let existing = project.sortedMilestones.flatMap { $0.goals ?? [] }.filter { $0.externalID.hasPrefix(prefix) }
        var byID = Dictionary(existing.map { ($0.externalID, $0) }, uniquingKeysWith: { a, _ in a })
        var touched: Set<Milestone.ID> = []

        for (i, item) in incoming.enumerated() {
            guard let target = milestone(checkpoint: item.checkpoint, due: item.due, in: project) else { continue }
            let goal: Goal
            if let g = byID.removeValue(forKey: item.externalID) {
                goal = g
                // Don't pull goals out of a checkpoint that's already completed.
                if g.milestone?.id != target.id, !(g.milestone?.isDone ?? false), !target.isDone {
                    g.milestone = target
                }
            } else {
                goal = Goal(title: item.title, source: source, externalID: item.externalID, order: i)
                context.insert(goal)
                goal.milestone = target
            }
            goal.title = item.title
            goal.detail = item.detail
            goal.url = item.url
            goal.order = i
            goal.metricKey = item.metricKey
            goal.target = item.target
            if item.metricKey == nil || item.done { goal.setDone(item.done) }
            if let m = goal.milestone { touched.insert(m.id) }
        }

        // Removed upstream: drop unless already done (keeps the record of what was achieved).
        for g in byID.values where !g.isDone { context.delete(g) }

        // Remote goals take priority over AI suggestions on the same checkpoint.
        for m in project.sortedMilestones where touched.contains(m.id) {
            for g in m.goals ?? [] where g.source == .ai && !g.isDone { context.delete(g) }
        }
    }

    // MARK: Metric goals

    static func value(for key: String, project: Project, refresher: DataRefresher) -> Double? {
        if let k = MetricKey(rawValue: key) { return refresher.value(k, for: project) }
        return refresher.extras(for: project).first { $0.key == key }?.value
    }

    static func evaluateMetricGoals(project: Project, refresher: DataRefresher, now: Date = .now) {
        for g in project.sortedMilestones.flatMap({ $0.goals ?? [] }) where !g.isDone {
            guard let key = g.metricKey, let target = g.target,
                  let v = value(for: key, project: project, refresher: refresher), v >= target else { continue }
            g.setDone(true, at: now)
        }
    }

    /// Rounds up to a friendly number with two significant digits: 1234 → 1300, 87 → 90, 3 → 10.
    static func niceTarget(_ x: Double) -> Double {
        guard x > 0 else { return 10 }
        let e = floor(log10(x))
        let mantissa = x / pow(10, e)
        let step = pow(10, e - 1) * (mantissa < 3 ? 1 : 5)
        return max(10, (x / step).rounded(.up) * step)
    }

    /// A stretch goal: current pace extended to the review date, plus 15%, and never trivially close.
    static func stretchTarget(current: Double, dailyRate: Double, daysLeft: Int) -> Double {
        let projected = current + max(dailyRate, 0) * Double(max(daysLeft, 1))
        return niceTarget(max(projected * 1.15, current * 1.2, current + 10))
    }

    static func dailyRate(_ key: MetricKey, project: Project) -> Double {
        let points = project.sortedSnapshots
        guard let last = points.last else { return 0 }
        let weekAgo = last.date.addingTimeInterval(-7 * 86_400)
        guard let first = points.first(where: { $0.date >= weekAgo }), last.date > first.date else { return 0 }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        return (last.value(key) - first.value(key)) / max(days, 1)
    }

    /// During the observe phase the traction review gets data-driven targets (once).
    static func ensureTractionTargets(project: Project, refresher: DataRefresher, context: ModelContext, now: Date = .now) {
        guard project.phase(on: now) == .observing,
              let review = project.sortedMilestones.last, !review.isDone,
              !(review.goals ?? []).contains(where: { $0.source == .metric }) else { return }
        let daysLeft = Date.days(from: now, to: review.dueDate)
        var order = 100
        for key in [MetricKey.visits, .revenue] {
            guard let current = refresher.value(key, for: project) else { continue }
            if key == .revenue && current <= 0 { continue }
            let target = stretchTarget(current: current, dailyRate: dailyRate(key, project: project), daysLeft: daysLeft)
            let title = key == .revenue ? "Reach \(MetricKey.money(target)) revenue" : "Reach \(MetricKey.count(target)) visits"
            let g = Goal(title: title, source: .metric, externalID: "metric:\(key.rawValue)", order: order)
            g.metricKey = key.rawValue
            g.target = target
            context.insert(g)
            g.milestone = review
            order += 1
        }
    }

    // MARK: Local goals

    static func addGoals(_ titles: [String], source: GoalSource, to milestone: Milestone, context: ModelContext) {
        let start = (milestone.goals ?? []).count
        for (i, t) in titles.enumerated() {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let g = Goal(title: trimmed, source: source, order: start + i)
            context.insert(g)
            g.milestone = milestone
        }
    }

    // MARK: Auto-complete

    /// Completes every open checkpoint whose goals are all done. Returns the ones completed.
    @discardableResult
    static func autoComplete(projects: [Project], profile: Profile, celebration: CelebrationCenter?, now: Date = .now) -> [Milestone] {
        var done: [Milestone] = []
        for m in projects.flatMap({ $0.sortedMilestones }) where !m.isDone && m.hasGoals {
            guard (m.goals ?? []).allSatisfy(\.isDone) else { continue }
            ScheduleEngine.complete(m, profile: profile, celebration: celebration, now: now)
            done.append(m)
        }
        return done
    }

    /// Everything that should happen after new data arrived.
    static func afterRefresh(projects: [Project], profile: Profile, refresher: DataRefresher,
                             celebration: CelebrationCenter?, context: ModelContext, now: Date = .now) {
        for p in projects where p.isActive {
            ensureTractionTargets(project: p, refresher: refresher, context: context, now: now)
            evaluateMetricGoals(project: p, refresher: refresher, now: now)
        }
        autoComplete(projects: projects, profile: profile, celebration: celebration, now: now)
        try? context.save()
    }
}
