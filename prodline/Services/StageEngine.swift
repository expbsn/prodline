import Foundation
import SwiftData

/// Moves projects through their stages and keeps checkpoints in the right one.
enum StageEngine {
    // MARK: Upkeep

    /// After every refresh: converts projects from before stages, files checkpoints into stages, and moves
    /// the checkpoints of stages ahead when the current one runs over.
    static func tidy(_ projects: [Project], profile: Profile?, now: Date = .now) {
        for p in projects where !p.isDraft {
            migrate(p, now: now)
            assignStages(p)
            realign(p, profile: profile, now: now)
        }
    }

    /// Saves the Build and Observe stages a project from before stages is read with.
    static func migrate(_ p: Project, now: Date = .now) {
        guard p.stagesData == nil else { return }
        p.stages = p.legacyStages(on: now)
    }

    /// Gives every checkpoint a stage (the one its date falls in) and its day within it.
    static func assignStages(_ p: Project) {
        let spans = p.spans()
        let launchStage = p.launchStageIndex
        for m in p.milestones ?? [] {
            let known: StageSpan? = spans.first { $0.stage.id.uuidString == m.stageID }
            var span: StageSpan? = known
            if span == nil, m.isLaunch { span = spans[safe: launchStage] }
            if span == nil { span = spans.first { $0.contains(m.dueDate) } }
            if span == nil { span = m.dueDate < p.startDate ? spans.first : spans.last }
            guard let span else { continue }
            if known == nil { m.stageID = span.stage.id.uuidString }
            if m.stageDay < 0 { m.stageDay = max(0, Date.days(from: span.start, to: m.dueDate)) }
        }
    }

    /// Open checkpoints keep their day within their stage: those ahead move back when the current stage runs
    /// over and forward when it finishes early, and a stage that just started places its own from its start. (prodline.json plans keep the file's days.)
    @discardableResult
    static func realign(_ p: Project, profile: Profile?, now: Date = .now) -> [Milestone] {
        guard !p.followsPlanFile, !p.isDraft else { return [] }
        let spans = p.spans(on: now)
        var moved: [Milestone] = []
        for m in p.milestones ?? [] where !m.isDone && m.stageDay >= 0 {
            guard let span = spans.first(where: { $0.stage.id.uuidString == m.stageID }), span.state != .done else { continue }
            let due = span.start.adding(days: min(m.stageDay, max(0, span.stage.days - 1)))
            guard due != m.dueDate else { continue }
            m.dueDate = due
            moved.append(m)
        }
        if let profile, profile.remindersEnabled {
            for m in moved { Notifier.cancel(m); Notifier.schedule(m, profile: profile) }
        }
        return moved
    }

    // MARK: Moving on

    /// What's left before the current stage can be finished: open checkpoints and their open goals.
    struct Remaining { var checkpoints: Int; var goals: Int; var isEmpty: Bool { checkpoints == 0 } }

    static func remaining(_ p: Project, now: Date = .now) -> Remaining? {
        guard let span = p.currentSpan(on: now) else { return nil }
        let open = p.milestones(in: span.stage).filter { !$0.isDone }
        return Remaining(checkpoints: open.count, goals: open.map { $0.openGoals.count }.reduce(0, +))
    }

    static func canFinishStage(_ p: Project, now: Date = .now) -> Bool {
        remaining(p, now: now)?.isEmpty ?? false
    }

    struct Finished { let stage: Stage; let next: Stage?; let daysEarly: Int; let xp: Int; let shipped: Bool }

    /// Confirms the current stage done (today) and starts the next. Finishing early pays a small bonus;
    /// finishing the launch stage is the ship. A deciding stage goes through the verdict instead.
    @discardableResult
    static func finishStage(_ p: Project, profile: Profile, now: Date = .now) -> Finished? {
        guard let span = p.currentSpan(on: now), canFinishStage(p, now: now) else { return nil }
        let today = now.startOfDay
        let early = max(0, Date.days(from: today, to: span.plannedLastDay))
        let shipped = span.index == p.launchStageIndex
        var all = p.stages
        all[span.index].finishedAt = today
        p.stages = all
        var xp = 0
        if early > 0 {
            xp = min(ScheduleEngine.earlyXPCap, early * ScheduleEngine.earlyXPPerDay)
            profile.xp += xp
        }
        realign(p, profile: profile, now: now)
        return Finished(stage: span.stage, next: all[safe: span.index + 1], daysEarly: early, xp: xp, shipped: shipped)
    }

    /// The sticky button: finish, save, celebrate (the ship moment for the launch stage when early).
    @MainActor
    static func finishStageNow(_ p: Project, profile: Profile, projects: [Project], celebration: CelebrationCenter,
                               context: ModelContext) {
        guard let r = finishStage(p, profile: profile) else { return }
        try? context.save()
        if r.shipped && r.daysEarly > 0 {
            celebration.celebrateShip(.init(daysEarly: r.daysEarly, plannedDays: r.stage.days, project: p.name, accent: p.accent, xp: r.xp))
        } else {
            let next = r.next.map { "\($0.name) starts today" } ?? "That was the last stage"
            let title = r.shipped ? "\(p.name) is out" : "\(r.stage.name) done"
            celebration.fire(title: r.xp > 0 ? "\(title) · +\(r.xp) XP" : title, subtitle: next, accent: p.accent,
                             xp: r.xp, kind: .checkpoint)
        }
        Streak.refresh(profile, projects: projects, celebration: celebration)
    }

    /// Keep after a decision: move on when stages follow, otherwise watch `days` more from today.
    static func keep(_ p: Project, days: Int, now: Date = .now) {
        guard let span = p.currentSpan(on: now) else { return }
        var all = p.stages
        if span.index < all.count - 1 {
            all[span.index].finishedAt = now.startOfDay
            p.stages = all
        } else {
            let ends = closingCheckpoints(p, stages: all)
            all[span.index].days = max(all[span.index].days, Date.days(from: span.start, to: now.startOfDay) + days)
            p.stages = all
            moveToEnds(ends, stages: all, spans: p.spans(on: now))
        }
        realign(p, profile: nil, now: now)
    }

    /// Open checkpoints on their stage's last day (the launch, "Build done", the review), which stay on
    /// the last day when the stage's length changes.
    private static func closingCheckpoints(_ p: Project, stages: [Stage]) -> [Milestone] {
        (p.milestones ?? []).filter { m in
            !m.isDone && stages.contains { $0.id.uuidString == m.stageID && m.stageDay == $0.days - 1 }
        }
    }

    private static func moveToEnds(_ ms: [Milestone], stages: [Stage], spans: [StageSpan]) {
        for m in ms {
            guard let s = stages.first(where: { $0.id.uuidString == m.stageID }) else { continue }
            m.stageDay = max(0, s.days - 1)
            if let span = spans.first(where: { $0.stage.id == s.id }) { m.dueDate = span.plannedLastDay }
        }
    }

    /// Pivot or kill: every stage left closes today.
    static func closeAll(_ p: Project, now: Date = .now) {
        var all = p.stages
        for i in all.indices where all[i].finishedAt == nil { all[i].finishedAt = now.startOfDay }
        p.stages = all
    }

    // MARK: Planning

    /// The checkpoints a plan starts with: checkpoints on the chosen weekdays inside each working stage, a
    /// launch at the end of the launch stage, a closing checkpoint for every other working stage, and a
    /// traction review at the end of each deciding stage.
    static func defaultCheckpoints(stages: [Stage], start: Date, weekdayMask: Int) -> [PlannedCheckpoint] {
        let cal = Calendar.current
        let launch = stages.firstIndex(where: \.decides).map { max(0, $0 - 1) } ?? max(0, stages.count - 1)
        var out: [PlannedCheckpoint] = []
        var cursor = start.startOfDay
        for (i, stage) in stages.enumerated() {
            let days = max(1, stage.days)
            if stage.decides {
                out.append(PlannedCheckpoint(stageID: stage.id, day: days - 1, title: "Traction review"))
            } else {
                if days > 2 {
                    for d in 1..<(days - 1) {
                        let wd = cal.component(.weekday, from: cursor.adding(days: d))
                        if weekdayMask & (1 << (wd - 1)) != 0 {
                            out.append(PlannedCheckpoint(stageID: stage.id, day: d, title: "Checkpoint"))
                        }
                    }
                }
                let isLaunch = i == launch && !(stages.first?.decides ?? false)
                out.append(PlannedCheckpoint(stageID: stage.id, day: days - 1,
                                             title: isLaunch ? "Ship it" : "\(stage.name) done", isLaunch: isLaunch))
            }
            cursor = cursor.adding(days: days)
        }
        return numbered(out, stages: stages)
    }

    /// "Checkpoint 1, 2, 3" in date order, like real checkpoints.
    static func numbered(_ plan: [PlannedCheckpoint], stages: [Stage]) -> [PlannedCheckpoint] {
        let order = Dictionary(uniqueKeysWithValues: stages.enumerated().map { ($1.id, $0) })
        var n = 1
        return sorted(plan, stages: stages).map { c in
            var c = c
            guard order[c.stageID] != nil, !c.titleIsCustom, !c.isLaunch, ScheduleEngine.isAutoName(c.title) else { return c }
            c.title = "Checkpoint \(n)"
            n += 1
            return c
        }
    }

    static func sorted(_ plan: [PlannedCheckpoint], stages: [Stage]) -> [PlannedCheckpoint] {
        let order = Dictionary(uniqueKeysWithValues: stages.enumerated().map { ($1.id, $0) })
        return plan.sorted { (order[$0.stageID] ?? .max, $0.day) < (order[$1.stageID] ?? .max, $1.day) }
    }

    /// The date a planned checkpoint falls on if the plan starts on `start`.
    static func date(of c: PlannedCheckpoint, stages: [Stage], start: Date) -> Date {
        var cursor = start.startOfDay
        for s in stages {
            if s.id == c.stageID { return cursor.adding(days: min(c.day, max(0, s.days - 1))) }
            cursor = cursor.adding(days: max(1, s.days))
        }
        return cursor
    }

    /// Puts a plan's checkpoints (and goals) on a project that starts on its start date.
    static func materialize(_ plan: [PlannedCheckpoint], into p: Project, profile: Profile, context: ModelContext) -> [Milestone] {
        let stages = p.stages
        var made: [Milestone] = []
        for c in sorted(plan, stages: stages) where stages.contains(where: { $0.id == c.stageID }) {
            let m = Milestone(title: c.title, dueDate: date(of: c, stages: stages, start: p.startDate), isLaunch: c.isLaunch)
            m.titleIsCustom = c.titleIsCustom
            m.stageID = c.stageID.uuidString
            m.stageDay = c.day
            context.insert(m)
            m.project = p
            for source in [GoalSource.ai, .manual] {
                GoalEngine.addGoals(c.goals.filter { $0.sourceRaw == source.rawValue }.map(\.title), source: source, to: m, context: context)
            }
            made.append(m)
        }
        ScheduleEngine.renumber(p)
        return made
    }

    /// Starts a draft (or a freshly made project) on `date`: its planned checkpoints become real, with reminders.
    static func start(_ p: Project, on date: Date, profile: Profile, context: ModelContext) {
        p.startDate = date.startOfDay
        p.isDraft = false
        var all = p.stages
        for i in all.indices { all[i].finishedAt = nil }
        p.stages = all
        let made = materialize(p.plannedCheckpoints, into: p, profile: profile, context: context)
        p.plannedCheckpoints = []
        if profile.remindersEnabled { for m in made { Notifier.schedule(m, profile: profile) } }
    }

    // MARK: Editing a running plan

    /// New stages for a project: finished ones stay as they were, checkpoints of removed stages move to
    /// the nearest stage left, and everything ahead moves to the new dates.
    static func replaceStages(_ p: Project, with new: [Stage], startDate: Date? = nil, profile: Profile?, now: Date = .now) {
        let old = p.stages(on: now)
        let ends = closingCheckpoints(p, stages: old)
        var kept = new
        // Finished stages can't be edited or removed.
        for (i, s) in old.enumerated() where s.finishedAt != nil {
            if let j = kept.firstIndex(where: { $0.id == s.id }) { kept[j].finishedAt = s.finishedAt; kept[j].days = s.days }
            else { kept.insert(s, at: min(i, kept.count)) }
        }
        guard !kept.isEmpty else { return }
        if let startDate {
            let delta = Date.days(from: p.startDate, to: startDate)
            p.startDate = startDate.startOfDay
            if p.followsPlanFile { for m in p.milestones ?? [] { m.dueDate = m.dueDate.adding(days: delta) } }
        }
        let keptIDs = Set(kept.map(\.id.uuidString))
        for m in p.milestones ?? [] where !keptIDs.contains(m.stageID) {
            let oldIndex = old.firstIndex { $0.id.uuidString == m.stageID } ?? 0
            let target = (0...oldIndex).reversed().compactMap { i in old[safe: i].flatMap { s in keptIDs.contains(s.id.uuidString) ? s : nil } }.first
                ?? kept.first!
            m.stageID = target.id.uuidString
            m.stageDay = max(0, target.days - 1)
        }
        p.stages = kept
        // Days inside a stage that got shorter; closing checkpoints stay on the last day.
        for m in p.milestones ?? [] {
            if let s = kept.first(where: { $0.id.uuidString == m.stageID }), m.stageDay >= s.days { m.stageDay = max(0, s.days - 1) }
        }
        for m in ends { if let s = kept.first(where: { $0.id.uuidString == m.stageID }) { m.stageDay = max(0, s.days - 1) } }
        // The current stage's checkpoints follow too when the plan changes (realign only moves stages ahead).
        let spans = p.spans(on: now)
        for m in p.milestones ?? [] where !m.isDone && !p.followsPlanFile {
            guard let span = spans.first(where: { $0.stage.id.uuidString == m.stageID }), span.state != .done, m.stageDay >= 0 else { continue }
            m.dueDate = span.start.adding(days: min(m.stageDay, max(0, span.stage.days - 1)))
        }
        if let profile, profile.remindersEnabled {
            for m in p.sortedMilestones where !m.isDone { Notifier.cancel(m); Notifier.schedule(m, profile: profile) }
        }
    }
}

extension Profile {
    var stageTemplate: [Stage] {
        get {
            if let data = stageTemplateData, let s = try? JSONDecoder().decode([Stage].self, from: data), !s.isEmpty { return s }
            // Fixed ids, so reading the default twice gives the same stages (views key on them).
            var d = Stage.defaults(buildDays: buildDays, observeDays: observeDays)
            d[0].id = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
            d[1].id = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
            return d
        }
        set { stageTemplateData = try? JSONEncoder().encode(newValue) }
    }

    /// A fresh copy of the template for a new project (new ids, nothing finished).
    var newStages: [Stage] {
        stageTemplate.map { Stage(name: $0.name, days: $0.days, decides: $0.decides) }
    }
}
