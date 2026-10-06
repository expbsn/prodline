import Foundation
import SwiftData
import UserNotifications

enum ScheduleEngine {
    // MARK: Milestones

    /// Checkpoints on the chosen weekdays during the build phase, a launch day, and a traction review.
    static func makeMilestones(for p: Project, weekdayMask: Int) -> [Milestone] {
        let cal = Calendar.current
        var out: [Milestone] = []
        var n = 1
        // Checkpoints fall strictly between start and launch day.
        if p.buildDays > 2 {
            for d in 1..<(p.buildDays - 1) {
                let date = p.startDate.adding(days: d)
                let wd = cal.component(.weekday, from: date)
                if weekdayMask & (1 << (wd - 1)) != 0 {
                    out.append(Milestone(title: "Checkpoint \(n)", dueDate: date))
                    n += 1
                }
            }
        }
        out.append(Milestone(title: "Ship it", dueDate: p.launchDay, isLaunch: true))
        out.append(Milestone(title: "Traction review", dueDate: p.observeEnd.adding(days: -1)))
        return out
    }

    // MARK: Editing checkpoints

    /// An empty name goes back to the automatic "Checkpoint n".
    static func rename(_ m: Milestone, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        m.titleIsCustom = !name.isEmpty
        m.title = name.isEmpty ? "Checkpoint" : name
        if let p = m.project { renumber(p) }
    }

    static func reschedule(_ m: Milestone, to date: Date, profile: Profile?) {
        m.dueDate = date.startOfDay
        m.missed = false
        if let p = m.project { renumber(p) }
        Notifier.cancel(m)
        if let profile, profile.remindersEnabled, !m.isDone { Notifier.schedule(m, hour: profile.reminderHour) }
    }

    @discardableResult
    static func addCheckpoint(to p: Project, title raw: String, due: Date, profile: Profile?, context: ModelContext) -> Milestone {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = Milestone(title: name.isEmpty ? "Checkpoint" : name, dueDate: due)
        m.titleIsCustom = !name.isEmpty
        context.insert(m)
        m.project = p
        renumber(p)
        if let profile, profile.remindersEnabled { Notifier.schedule(m, hour: profile.reminderHour) }
        return m
    }

    static func delete(_ m: Milestone, context: ModelContext) {
        let p = m.project
        Notifier.cancel(m)
        m.project = nil
        context.delete(m)
        if let p { renumber(p) }
    }

    /// Changes a running project's start date and phase lengths. Open checkpoints shift with the start,
    /// launch and traction review follow the new phase ends, and empty automatic checkpoints are redrawn
    /// on the checkpoint weekdays. Finished checkpoints, goals and custom names are kept.
    static func changeSchedule(_ p: Project, start: Date, buildDays: Int, observeDays: Int,
                               profile: Profile?, context: ModelContext) {
        // A prodline.json project counts its plan in days from the start: everything moves with it,
        // finished checkpoints included, so the next sync finds them where the file says.
        if p.followsPlanFile {
            let delta = Date.days(from: p.startDate, to: start)
            p.startDate = start.startOfDay
            p.buildDays = buildDays
            p.observeDays = observeDays
            for m in p.milestones ?? [] { m.dueDate = m.dueDate.adding(days: delta) }
            if let profile, profile.remindersEnabled {
                for m in p.sortedMilestones where !m.isDone {
                    Notifier.cancel(m)
                    Notifier.schedule(m, hour: profile.reminderHour)
                }
            }
            return
        }
        // Decide phase membership on the old schedule, before anything moves.
        let oldLaunch = p.launchDay
        let open = p.sortedMilestones.filter { !$0.isDone }
        let launch = open.first { $0.isLaunch }
        let observing = open.filter { !$0.isLaunch && $0.dueDate > oldLaunch }   // traction review & co.
        let building = open.filter { !$0.isLaunch && $0.dueDate <= oldLaunch }

        let delta = Date.days(from: p.startDate, to: start)
        p.startDate = start.startOfDay
        p.buildDays = buildDays
        p.observeDays = observeDays

        launch?.dueDate = p.launchDay
        let lastObserveDay = p.observeEnd.adding(days: -1)
        for m in observing {
            // The review sits on the last day; anything else keeps its distance from launch.
            let target = m.dueDate.adding(days: delta)
            m.dueDate = m === observing.last ? lastObserveDay : min(max(target, p.buildEnd), lastObserveDay)
        }

        // Empty automatic checkpoints are redrawn on the checkpoint weekdays; the rest shift and stay inside the build.
        var kept: [Milestone] = []
        for m in building {
            if !m.titleIsCustom && isAutoName(m.title) && !m.hasGoals {
                Notifier.cancel(m)
                m.project = nil
                context.delete(m)
            } else {
                m.dueDate = min(max(m.dueDate.adding(days: delta), p.startDate.adding(days: 1)), p.launchDay.adding(days: -1))
                kept.append(m)
            }
        }
        let taken = Set(kept.map(\.dueDate) + p.sortedMilestones.filter(\.isDone).map(\.dueDate))
        let mask = profile?.milestoneWeekdayMask ?? 0b0100010
        for m in makeMilestones(for: p, weekdayMask: mask) where !m.isLaunch && m.dueDate < p.launchDay && !taken.contains(m.dueDate) {
            context.insert(m)
            m.project = p
        }
        renumber(p)
        if let profile, profile.remindersEnabled {
            for m in p.sortedMilestones where !m.isDone {
                Notifier.cancel(m)
                Notifier.schedule(m, hour: profile.reminderHour)
            }
        }
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

    static func createProject(_ p: Project, profile: Profile, context: ModelContext) {
        context.insert(p)
        for m in makeMilestones(for: p, weekdayMask: profile.milestoneWeekdayMask) {
            context.insert(m)
            m.project = p
            if profile.remindersEnabled { Notifier.schedule(m, hour: profile.reminderHour) }
        }
        try? context.save()
    }

    /// When the next project should kick off, based on the cadence.
    static func nextProjectDate(projects: [Project], profile: Profile) -> Date {
        guard let last = projects.map(\.startDate).max() else { return Date.now.startOfDay }
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

    /// Building, with goals, and every one of them ticked: time for "Let's ship".
    static func canShip(_ p: Project, now: Date = .now) -> Bool {
        guard p.phase(on: now) == .building else { return false }
        let goals = (p.milestones ?? []).flatMap { $0.goals ?? [] }
        return !goals.isEmpty && goals.allSatisfy(\.isDone)
    }

    struct Shipped { let daysEarly: Int; let xp: Int }

    /// The "Let's ship" button: ship, update the streak, save, and celebrate (the big moment when it's early).
    @MainActor
    static func shipNow(_ p: Project, profile: Profile, projects: [Project], celebration: CelebrationCenter, context: ModelContext) {
        let r = ship(p, profile: profile)
        Streak.update(profile, projects: projects)
        try? context.save()
        if r.daysEarly > 0 {
            celebration.celebrateShip(.init(daysEarly: r.daysEarly, project: p.name, accent: p.accent, xp: r.xp))
        } else {
            celebration.fire(title: "Shipped! +\(r.xp) XP", subtitle: "\(p.name) is out · right on time", accent: p.accent,
                             xp: r.xp, kind: .checkpoint)
        }
    }

    /// Launch today. The build phase ends now, the launch checkpoint is done (on time, of course), leftover
    /// build checkpoints close with it, and the observe phase moves up so it keeps its full length.
    @discardableResult
    static func ship(_ p: Project, profile: Profile, now: Date = .now) -> Shipped {
        let today = now.startOfDay
        let oldLaunch = p.launchDay
        let early = max(0, Date.days(from: today, to: oldLaunch))
        // Sorted out on the old schedule: what belongs to the build and what to the observe phase.
        let open = p.sortedMilestones.filter { !$0.isDone }
        let building = open.filter { $0.isLaunch || $0.dueDate <= oldLaunch }
        let observing = open.filter { !$0.isLaunch && $0.dueDate > oldLaunch }

        var xp = 0
        if early > 0 {
            p.buildDays = max(1, Date.days(from: p.startDate, to: today) + 1)
            for m in observing {
                m.dueDate = m.dueDate.adding(days: -early)
                if profile.remindersEnabled { Notifier.cancel(m); Notifier.schedule(m, hour: profile.reminderHour) }
            }
            let bonus = min(earlyXPCap, early * earlyXPPerDay)
            profile.xp += bonus
            xp += bonus
        }
        for m in building {
            if m.dueDate > today { m.dueDate = today }
            xp += complete(m, profile: profile, celebration: nil, now: now)
        }
        return Shipped(daysEarly: early, xp: xp)
    }

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
        if m.project != nil, profile.remindersEnabled { Notifier.schedule(m, hour: profile.reminderHour) }
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
        let more = late.count > 1 ? " · \(late.count - 1) more late" : ""
        return ("\(m.title) is \(days) day\(days == 1 ? "" : "s") late",
                "\(p.name) · " + (open > 0 ? "\(open) goal\(open == 1 ? "" : "s") still open" : "tick it off when it's done") + more)
    }

    static func praise() -> String {
        ["Nailed it", "Right on time", "Look at you go", "Shipping machine", "Crushing it", "That's the spirit"].randomElement()!
    }
}

enum Notifier {
    static func requestAuth() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ m: Milestone, hour: Int) {
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
        add(m.id.uuidString + "-pm", hour: 18, title: "Still time today",
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
            schedule(m, hour: profile.reminderHour)
        }
        for p in projects { scheduleVerdict(p, hour: profile.reminderHour) }
    }

    /// The morning after the observe phase ends: time for keep, pivot or kill. Re-adding replaces it,
    /// so a changed schedule or a keep moves it along.
    static func scheduleVerdict(_ p: Project, hour: Int) {
        let id = "verdict-" + p.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard p.verdict != .pivot, p.verdict != .kill else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: p.observeEnd)
        comps.hour = hour
        guard let fire = Calendar.current.date(from: comps), fire > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(p.name): decision time"
        content.body = p.criteria.isEmpty
            ? "The observe phase is over. Keep it, pivot it or kill it?"
            : "The observe phase is over. See how it did against your targets, then make the call."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}
