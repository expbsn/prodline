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

    static func repoPreview(_ snap: GitHubSnapshot, dues: [Date], start: Date) -> RepoPreview {
        func dayDate(_ d: Int?) -> Date? { d.map { start.startOfDay.adding(days: max($0, 1) - 1) } }
        var goals = Array(repeating: [(title: String, source: GoalSource)](), count: dues.count)
        var names = Array(repeating: String?.none, count: dues.count)
        for item in githubIncoming(snap) {
            if let i = slot(checkpoint: item.checkpoint, due: item.due, dues: dues), !item.done { goals[i].append((item.title, .github)) }
        }
        for g in snap.planFile?.goals ?? [] where !(g.done ?? false) {
            if let i = slot(checkpoint: g.checkpoint, due: dayDate(g.day) ?? g.due, dues: dues) { goals[i].append((g.title, .repoFile)) }
        }
        for c in snap.planFile?.checkpoints ?? [] {
            if let i = slot(checkpoint: c.checkpoint, due: dayDate(c.day) ?? c.due, dues: dues) { names[i] = c.title }
        }
        return RepoPreview(goals: goals, names: names, hasPlanFile: snap.planFile != nil)
    }

    // MARK: Remote sync

    static func syncAPI(_ goals: [MetricsPayload.RemoteGoal], project: Project, context: ModelContext) {
        guard !project.followsPlanFile else { return }
        let incoming = goals.map {
            Incoming(externalID: "api:\($0.id)", title: $0.title, detail: $0.detail ?? "", url: $0.url ?? "",
                     checkpoint: $0.checkpoint, due: $0.day.map { date(ofDay: $0, in: project) } ?? $0.due, done: $0.done ?? false,
                     metricKey: $0.metric?.key, target: $0.metric?.target)
        }
        sync(incoming, prefix: "api:", source: .api, project: project, context: context)
    }

    /// GitHub issues become goals when they belong to a GitHub milestone or carry the `prodline` label.
    /// A milestone's due date picks the checkpoint; without one, the Nth milestone maps to the Nth checkpoint.
    static func syncGitHub(_ snap: GitHubSnapshot, project: Project, context: ModelContext) {
        if let plan = snap.planFile {
            // prodline.json is the plan: its checkpoints and goals, nothing else.
            project.followsPlanFile = true
            applyPlan(plan, project: project, context: context)
            return
        }
        if snap.planFileError != nil { return }  // a broken file keeps what we have until it's fixed
        if project.followsPlanFile {
            // The file was removed: its open goals go, and the project plans normally again.
            project.followsPlanFile = false
            syncPlanFile([], project: project, context: context)
        }
        sync(githubIncoming(snap), prefix: "gh:", source: .github, project: project, context: context)
    }

    /// Makes the project mirror prodline.json exactly: one checkpoint per dated entry (or per goal due
    /// date when the file lists no checkpoints), the file's goals on them, and nothing else. Done
    /// checkpoints that aren't in the file go too; their goals are re-placed first so nothing is lost.
    /// Day N of the project (day 1 = start date) as a calendar date.
    static func date(ofDay day: Int, in project: Project) -> Date { project.startDate.adding(days: max(day, 1) - 1) }

    static func applyPlan(_ plan: GitHubSnapshot.PlanFile, project: Project, context: ModelContext) {
        var targets: [(title: String?, date: Date)] = (plan.checkpoints ?? []).compactMap { c in
            let d = c.day.map { date(ofDay: $0, in: project) } ?? c.due?.startOfDay
            return d.map { (c.title.trimmingCharacters(in: .whitespacesAndNewlines), $0) }
        }
        if targets.isEmpty {
            targets = Set(plan.goals.compactMap { g in g.day.map { date(ofDay: $0, in: project) } ?? g.due?.startOfDay })
                .sorted().map { (nil, $0) }
        }
        // One entry per day, in order.
        var seen = Set<Date>()
        targets = targets.sorted { $0.date < $1.date }.filter { seen.insert($0.date).inserted }
        guard !targets.isEmpty else {
            // Only positional goals: keep the checkpoints, but still nothing but the file's goals.
            for m in project.milestones ?? [] {
                for g in m.goals ?? [] where !g.externalID.hasPrefix("file:") { context.delete(g) }
            }
            syncPlanFile(plan.goals, project: project, context: context, strict: true)
            return
        }

        // A checkpoint per target day: reuse one already on that day (merging duplicates), else add it.
        var keep: [Milestone] = []
        for t in targets {
            let onDay = project.sortedMilestones.filter { $0.dueDate == t.date }
                .sorted { ($0.goals?.count ?? 0) > ($1.goals?.count ?? 0) }
            let m: Milestone
            if let first = onDay.first {
                m = first
                for extra in onDay.dropFirst() {
                    for g in extra.goals ?? [] { g.milestone = m }
                    extra.project = nil
                    context.delete(extra)
                }
            } else {
                m = Milestone(title: t.title ?? "Checkpoint", dueDate: t.date)
                context.insert(m)
                m.project = project
            }
            m.isLaunch = false
            if let title = t.title, !title.isEmpty, !m.titleIsCustom { m.title = title }
            keep.append(m)
        }

        // Everything else goes, after handing its goals to a kept checkpoint so the file sync can place them.
        let keepIDs = Set(keep.map(\.id))
        for m in project.milestones ?? [] where !keepIDs.contains(m.id) {
            for g in m.goals ?? [] { g.milestone = keep[0] }
            Notifier.cancel(m)
            m.project = nil
            context.delete(m)
        }
        // Only the file's goals stay.
        for m in keep {
            for g in m.goals ?? [] where !g.externalID.hasPrefix("file:") { context.delete(g) }
        }
        syncPlanFile(plan.goals, project: project, context: context, strict: true)
        ScheduleEngine.renumber(project)
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

    static func syncPlanFile(_ goals: [MetricsPayload.RemoteGoal], project: Project, context: ModelContext, strict: Bool = false) {
        // Chronological: by day/date, keeping the file's order within a day.
        let incoming = goals.enumerated().map { i, g in
            (i, Incoming(externalID: "file:\(g.id)", title: g.title, detail: g.detail ?? "", url: g.url ?? "",
                         checkpoint: g.checkpoint, due: g.day.map { date(ofDay: $0, in: project) } ?? g.due, done: g.done ?? false,
                         metricKey: g.metric?.key, target: g.metric?.target))
        }
        .sorted { ($0.1.due ?? .distantFuture, $0.0) < ($1.1.due ?? .distantFuture, $1.0) }
        .map(\.1)
        sync(incoming, prefix: "file:", source: .repoFile, project: project, context: context, strict: strict)
    }

    /// `strict`: goals always go where the source says, even out of a finished checkpoint.
    static func sync(_ incoming: [Incoming], prefix: String, source: GoalSource, project: Project, context: ModelContext,
                     strict: Bool = false) {
        let existing = project.sortedMilestones.flatMap { $0.goals ?? [] }.filter { $0.externalID.hasPrefix(prefix) }
        var byID = Dictionary(existing.map { ($0.externalID, $0) }, uniquingKeysWith: { a, _ in a })
        var touched: Set<Milestone.ID> = []

        for (i, item) in incoming.enumerated() {
            guard let target = milestone(checkpoint: item.checkpoint, due: item.due, in: project) else { continue }
            let goal: Goal
            if let g = byID.removeValue(forKey: item.externalID) {
                goal = g
                // Don't pull goals out of a checkpoint that's already completed.
                if g.milestone?.id != target.id, strict || (!(g.milestone?.isDone ?? false) && !target.isDone) {
                    g.milestone = target
                }
            } else {
                goal = Goal(title: item.title, source: source, externalID: item.externalID, order: i)
                context.insert(goal)
                goal.milestone = target
                // Goals that were already done before we ever saw them don't pay out.
                goal.xpAwarded = item.done
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
        guard !project.followsPlanFile, project.phase(on: now) == .observing,
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

    // MARK: Goal XP

    static let xpPerGoal = 3
    static let goalXPSinceKey = "xp.goalXPSince"

    /// Pays XP for every goal finished since we last looked, from any source (prodline.json, GitHub,
    /// your API, metric targets or ticked by hand). Each goal pays once; goals finished before this
    /// feature existed are marked without paying, so updating the app doesn't dump a pile of XP.
    @discardableResult
    static func awardGoalXP(projects: [Project], profile: Profile, celebration: CelebrationCenter?,
                            now: Date = .now, defaults: UserDefaults = .standard) -> Int {
        let since: Date
        if let d = defaults.object(forKey: goalXPSinceKey) as? Date { since = d } else {
            since = now
            defaults.set(now, forKey: goalXPSinceKey)
        }
        var paid: [(goal: Goal, project: Project)] = []
        for p in projects {
            for g in p.sortedMilestones.flatMap({ $0.goals ?? [] }) where g.isDone && !g.xpAwarded {
                g.xpAwarded = true
                if (g.doneAt ?? .distantPast) >= since { paid.append((g, p)) }
            }
        }
        guard !paid.isEmpty else { return 0 }
        let xp = paid.count * xpPerGoal
        profile.xp += xp
        let projectsHit = Set(paid.map { $0.project.id })
        let subtitle: String
        if paid.count == 1 {
            subtitle = paid[0].goal.title
        } else if projectsHit.count == 1 {
            subtitle = "\(paid.count) goals done in \(paid[0].project.name)"
        } else {
            subtitle = "\(paid.count) goals done across \(projectsHit.count) projects"
        }
        celebration?.fire(title: "+\(xp) XP", subtitle: subtitle,
                          accent: projectsHit.count == 1 ? paid[0].project.accent : .neutral, confetti: false,
                          xp: xp, kind: .goals(paid.count))
        return xp
    }

    /// Everything that should happen after new data arrived.
    static func afterRefresh(projects: [Project], profile: Profile, refresher: DataRefresher,
                             celebration: CelebrationCenter?, context: ModelContext, now: Date = .now) {
        for p in projects where p.isActive {
            ensureTractionTargets(project: p, refresher: refresher, context: context, now: now)
            evaluateMetricGoals(project: p, refresher: refresher, now: now)
        }
        // Goal XP first; a checkpoint that completes in the same pass then shows its own (bigger) banner.
        awardGoalXP(projects: projects, profile: profile, celebration: celebration, now: now)
        autoComplete(projects: projects, profile: profile, celebration: celebration, now: now)
        try? context.save()
    }
}
