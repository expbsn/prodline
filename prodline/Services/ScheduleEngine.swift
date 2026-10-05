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
            profile.streak += 1
            profile.bestStreak = max(profile.bestStreak, profile.streak)
            profile.completedOnTime += 1
        } else {
            gained = lateXP
            profile.completedLate += 1
        }
        profile.xp += gained

        let accent = m.project?.accent ?? .neutral
        if profile.level > oldLevel {
            celebration?.fire(title: "Level \(profile.level)", subtitle: "+\(gained) XP · you're on a roll", accent: accent)
        } else if onTime {
            celebration?.fire(title: m.isLaunch ? "Shipped! +\(gained) XP" : "+\(gained) XP",
                              subtitle: "\(praise()) · \(profile.streak) on time in a row", accent: accent)
        } else {
            celebration?.fire(title: "+\(gained) XP", subtitle: "Late beats never. Keep going.", accent: accent, confetti: false)
        }
        return gained
    }

    /// Flags deadlines that slipped past; resets the streak once per slip.
    @discardableResult
    static func evaluateMissed(projects: [Project], profile: Profile, now: Date = .now) -> Int {
        var count = 0
        for m in projects.flatMap({ $0.milestones ?? [] }) where m.isOverdue(on: now) && !m.missed {
            m.missed = true
            count += 1
        }
        if count > 0 { profile.streak = 0 }
        return count
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
            body: "\(m.title) · \(project.name).\(goalsText.isEmpty ? " Finish it and keep your streak alive." : goalsText)")
    }

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
            .removePendingNotificationRequests(withIdentifiers: [m.id.uuidString, m.id.uuidString + "-pm"])
    }

    static func rescheduleAll(projects: [Project], profile: Profile) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard profile.remindersEnabled else { return }
        for m in projects.flatMap({ $0.milestones ?? [] }) where !m.isDone {
            schedule(m, hour: profile.reminderHour)
        }
    }
}
