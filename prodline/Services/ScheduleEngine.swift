import Foundation
import SwiftData
import UserNotifications

enum ScheduleEngine {
    // MARK: Milestones

    /// The checkpoints a project's stages start with (see StageEngine.defaultCheckpoints), not yet inserted.
    static func makeMilestones(for p: Project, weekdayMask: Int) -> [Milestone] {
        let stages = p.stages
        return StageEngine.defaultCheckpoints(stages: stages, start: p.startDate, weekdayMask: weekdayMask).map { c in
            let m = Milestone(title: c.title, dueDate: StageEngine.date(of: c, stages: stages, start: p.startDate), isLaunch: c.isLaunch)
            m.stageID = c.stageID.uuidString
            m.stageDay = c.day
            return m
        }
    }

    // MARK: Editing checkpoints

    /// An empty name goes back to the automatic "Checkpoint n".
    static func rename(_ m: Milestone, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        m.titleIsCustom = !name.isEmpty
        m.title = name.isEmpty ? "Checkpoint" : name
        if let p = m.project { renumber(p) }
    }

    /// Moves a checkpoint to a date, and to a stage when given (else the one it's in).
    static func reschedule(_ m: Milestone, to date: Date, stage: Stage? = nil, profile: Profile?) {
        m.dueDate = date.startOfDay
        m.missed = false
        place(m, stage: stage)
        if let p = m.project { renumber(p) }
        Notifier.cancel(m)
        if let profile, profile.remindersEnabled, !m.isDone { Notifier.schedule(m, profile: profile) }
    }

    @discardableResult
    static func addCheckpoint(to p: Project, title raw: String, due: Date, stage: Stage? = nil, profile: Profile?,
                              context: ModelContext) -> Milestone {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = Milestone(title: name.isEmpty ? "Checkpoint" : name, dueDate: due)
        m.titleIsCustom = !name.isEmpty
        context.insert(m)
        m.project = p
        place(m, stage: stage)
        renumber(p)
        if let profile, profile.remindersEnabled { Notifier.schedule(m, profile: profile) }
        return m
    }

    static func delete(_ m: Milestone, context: ModelContext) {
        let p = m.project
        Notifier.cancel(m)
        m.project = nil
        context.delete(m)
        if let p { renumber(p) }
    }

    /// Files a checkpoint into `stage` (or the stage its date falls in) at its day within it.
    static func place(_ m: Milestone, stage: Stage?) {
        guard let p = m.project else { return }
        let spans = p.spans()
        let span = stage.flatMap { s in spans.first { $0.stage.id == s.id } }
            ?? spans.first { $0.contains(m.dueDate) }
            ?? (m.dueDate < p.startDate ? spans.first : spans.last)
        guard let span else { return }
        m.stageID = span.stage.id.uuidString
        m.stageDay = max(0, Date.days(from: span.start, to: m.dueDate))
    }

    /// Keeps automatic names in date order ("Checkpoint 1, 2, 3") after adds, moves and deletes.
    static func renumber(_ p: Project) {
        var n = 1
        for m in p.sortedMilestones where !m.isLaunch && !m.titleIsCustom && isAutoName(m.title) {
            m.title = "Checkpoint \(n)"
            n += 1
        }
    }

    static func isAutoName(_ title: String) -> Bool {
        title == "Checkpoint" || title.wholeMatch(of: /Checkpoint \d+/) != nil
    }

    /// Inserts a project. A draft keeps its planned checkpoints for later; otherwise they (or, without a
    /// plan, the stages' default checkpoints) become real ones with reminders.
    static func createProject(_ p: Project, profile: Profile, context: ModelContext) {
        context.insert(p)
        if p.stagesData == nil { p.stages = profile.newStages }
        if p.plannedCheckpoints.isEmpty {
            p.plannedCheckpoints = StageEngine.defaultCheckpoints(stages: p.stages, start: p.startDate,
                                                                  weekdayMask: profile.milestoneWeekdayMask)
        }
        if !p.isDraft { StageEngine.start(p, on: p.startDate, profile: profile, context: context) }
        try? context.save()
    }

    /// When the next project should kick off, based on the cadence.
    static func nextProjectDate(projects: [Project], profile: Profile) -> Date {
        guard let last = projects.filter({ !$0.isDraft }).map(\.startDate).max() else { return Date.now.startOfDay }
        return last.adding(days: profile.newProjectEveryDays)
    }

    /// Projects that are building or observing on `date`.
    static func overlap(on date: Date, projects: [Project]) -> Int {
        projects.filter { [.building, .observing].contains($0.phase(on: date)) }.count
    }

    // MARK: Completing & missing

    static let checkpointXP = 10
    static let launchXP = 50
    static let lateXP = 3

    // MARK: Shipping

    /// Bonus for every day a project ships before its launch day.
    static let earlyXPPerDay = 5
    static let earlyXPCap = 50

    @discardableResult
    static func complete(_ m: Milestone, profile: Profile, celebration: CelebrationCenter?, now: Date = .now) -> Int {
        guard !m.isDone else { return 0 }
        let onTime = now.startOfDay <= m.dueDate
        let oldLevel = profile.level
        m.completedAt = now
        Notifier.cancel(m)

        let gained: Int
        if onTime {
            gained = m.isLaunch ? launchXP : checkpointXP
            profile.completedOnTime += 1
        } else {
            gained = lateXP
            profile.completedLate += 1
        }
        profile.xp += gained
        m.xpEarned = gained
        m.countedOnTime = onTime
        Cheer.checkpoint(title: m.title, project: m.project?.name ?? "Your project", xp: gained,
                         daysEarly: Date.days(from: now.startOfDay, to: m.dueDate), isLaunch: m.isLaunch,
                         level: profile.level > oldLevel ? profile.level : nil)

        let accent = m.project?.accent ?? .neutral
        if profile.level > oldLevel {
            celebration?.fire(title: "Level \(profile.level)", subtitle: "+\(gained) XP · you're on a roll", accent: accent,
                              xp: gained, kind: .checkpoint)
        } else if onTime {
            celebration?.fire(title: m.isLaunch ? "Shipped! +\(gained) XP" : "+\(gained) XP",
                              subtitle: "\(praise()) · right on time", accent: accent,
                              xp: gained, kind: .checkpoint)
        } else {
            celebration?.fire(title: "+\(gained) XP", subtitle: "Late beats never. Keep going.", accent: accent, confetti: false,
                              xp: gained, kind: .checkpoint)
        }
        return gained
    }

    /// Marks a finished checkpoint as not done and takes back what finishing it paid
    /// (XP, the on-time count and the streak step). Returns the XP removed.
    @discardableResult
    static func uncomplete(_ m: Milestone, profile: Profile, now: Date = .now) -> Int {
        guard m.isDone else { return 0 }
        m.completedAt = nil
        return settleUndone(m, profile: profile, now: now)
    }

    /// Books back a checkpoint that is no longer done (undone by hand, or reopened by the plan file).
    @discardableResult
    static func settleUndone(_ m: Milestone, profile: Profile, now: Date = .now) -> Int {
        guard !m.isDone, m.xpEarned > 0 else { return 0 }
        let xp = m.xpEarned
        profile.xp = max(0, profile.xp - xp)
        if m.countedOnTime {
            profile.completedOnTime = max(0, profile.completedOnTime - 1)
        } else {
            profile.completedLate = max(0, profile.completedLate - 1)
        }
        m.xpEarned = 0
        m.countedOnTime = false
        m.missed = false   // evaluated again; overdue checkpoints get marked missed on the next pass
        if m.project != nil, profile.remindersEnabled { Notifier.schedule(m, profile: profile) }
        return xp
    }

    /// Flags deadlines that slipped past (the day streak is separate: see Streak).
    @discardableResult
    static func evaluateMissed(projects: [Project], profile: Profile, now: Date = .now) -> Int {
        var count = 0
        for m in projects.flatMap({ $0.milestones ?? [] }) where m.isOverdue(on: now) && !m.missed {
            m.missed = true
            count += 1
        }
        return count
    }

    /// The most urgent late checkpoint that still has work open, as an in-app reminder.
    static func lateReminder(projects: [Project], now: Date = .now) -> (title: String, subtitle: String)? {
        let late = projects.flatMap { $0.sortedMilestones }
            .filter { m in
                guard !m.isDone, m.isOverdue(on: now), let phase = m.project?.phase(on: now) else { return false }
                return phase == .building || phase == .observing
            }
            .sorted { $0.dueDate > $1.dueDate }
        guard let m = late.first, let p = m.project else { return nil }
        let days = Date.days(from: m.dueDate, to: now)
        let open = m.openGoals.count
        // One line: the project, what to do, and how many others are late.
        let more = late.count > 1 ? " · \(late.count - 1) more late" : ""
        let todo = open > 0 ? "\(open) goal\(open == 1 ? "" : "s") open" : late.count > 1 ? "tick it off" : "tick it off when it's done"
        return ("\(m.title) is \(days) day\(days == 1 ? "" : "s") late", "\(p.name) · " + todo + more)
    }

    static func praise() -> String {
        ["Nailed it", "Right on time", "Look at you go", "Shipping machine", "Crushing it", "That's the spirit"].randomElement()!
    }
}

enum Notifier {
    static func requestAuth() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ m: Milestone, profile: Profile) {
        schedule(m, hour: profile.reminderHour, nudge: profile.nudgeHour)
    }

    static func schedule(_ m: Milestone, hour: Int, nudge: Int = 18) {
        guard let project = m.project else { return }
        let center = UNUserNotificationCenter.current()
        func add(_ id: String, hour: Int, title: String, body: String) {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: m.dueDate)
            comps.hour = hour
            guard let fire = Calendar.current.date(from: comps), fire > .now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        let open = m.openGoals.map(\.title)
        let goalsText = open.isEmpty ? "" : " Left: " + open.prefix(2).joined(separator: ", ") + (open.count > 2 ? " +\(open.count - 2)" : "") + "."
        add(m.id.uuidString, hour: hour, title: "\(project.name): deadline day",
            body: "\(m.title) is due today.\(goalsText.isEmpty ? " You've got this." : goalsText)")
        add(m.id.uuidString + "-pm", hour: max(nudge, hour + 1), title: "Still time today",
            body: "\(m.title) · \(project.name).\(goalsText.isEmpty ? " Finish it and keep your streak going." : goalsText)")
        // If it slips, keep nudging for a few days; completing the checkpoint cancels these.
        for day in 1...lateDays {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: m.dueDate.adding(days: day))
            comps.hour = hour
            guard let fire = Calendar.current.date(from: comps), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(project.name): \(m.title) is \(day) day\(day == 1 ? "" : "s") late"
            content.body = open.isEmpty
                ? "Tick it off when it's done. Late still earns XP."
                : "Still open: " + open.prefix(2).joined(separator: ", ") + (open.count > 2 ? " +\(open.count - 2)" : "") + ". Late still earns XP."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: m.id.uuidString + "-late-\(day)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    /// How many days after a missed deadline the late reminders keep coming.
    static let lateDays = 3

    /// A GitHub-aware nudge: the repo has gone quiet while a checkpoint is coming up.
    static func staleRepoNudge(project: Project, hour: Int, now: Date = .now) {
        let id = "stale-" + project.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard project.phase(on: now) == .building, let last = project.lastCommitAt,
              now.timeIntervalSince(last) > 2 * 86_400,
              let next = project.nextMilestone, Date.days(from: now, to: next.dueDate) <= 2 else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        if let fire = Calendar.current.date(from: comps), fire <= now {
            comps = Calendar.current.dateComponents([.year, .month, .day], from: now.adding(days: 1))
            comps.hour = hour
        }
        let content = UNMutableNotificationContent()
        content.title = "\(project.name) has gone quiet"
        let left = next.openGoals.count
        content.body = "No commits since \(last.formatted(.dateTime.weekday(.wide))). \(next.title) is due \(next.dueDate.formatted(.dateTime.weekday(.wide)))" + (left > 0 ? " with \(left) goal\(left == 1 ? "" : "s") left." : ".")
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    /// Demo: a realistic deadline reminder in 5 seconds.
    static func sendTest(projects: [Project]) {
        let m = projects.flatMap { $0.sortedMilestones }.first { !$0.isDone }
        let content = UNMutableNotificationContent()
        content.title = m.flatMap { $0.project.map { "\($0.name): deadline day" } } ?? "Prodline: deadline day"
        let open = m?.openGoals.map(\.title) ?? []
        content.body = (m?.title ?? "Checkpoint 1") + " is due today." + (open.isEmpty ? " You've got this." : " Left: " + open.prefix(2).joined(separator: ", ") + ".")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "test-" + UUID().uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    static func cancel(_ m: Milestone) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [m.id.uuidString, m.id.uuidString + "-pm"]
                                               + (1...lateDays).map { m.id.uuidString + "-late-\($0)" })
    }

    static func rescheduleAll(projects: [Project], profile: Profile) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard profile.remindersEnabled else { return }
        for m in projects.flatMap({ $0.milestones ?? [] }) where !m.isDone {
            schedule(m, profile: profile)
        }
        for p in projects { scheduleVerdict(p, hour: profile.reminderHour) }
        StreakNudge.schedule(profile)
        WeeklyReview.scheduleNotification(enabled: true)
    }

    /// The morning after the next stage that ends with the call is planned to end: time for keep, pivot or
    /// kill. Re-adding replaces it, so a changed plan or a keep moves it along.
    static func scheduleVerdict(_ p: Project, hour: Int) {
        let id = "verdict-" + p.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard p.verdict != .pivot, p.verdict != .kill, !p.isDraft,
              let span = p.spans().first(where: { $0.stage.decides && $0.state != .done }) else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: span.plannedEnd)
        comps.hour = hour
        guard let fire = Calendar.current.date(from: comps), fire > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(p.name): decision time"
        content.body = p.criteria.isEmpty
            ? "\(span.stage.name) is over. Keep it, pivot it or kill it?"
            : "\(span.stage.name) is over. See how it did against your targets, then make the call."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}
