import Foundation
import SwiftData
import UserNotifications

enum ScheduleEngine {
    // MARK: Milestones

    /// Checkpoints on the user's chosen weekdays during the build phase, a launch day, and a traction review.
    static func makeMilestones(for p: Project, weekdayMask: Int) -> [Milestone] {
        let cal = Calendar.current
        var out: [Milestone] = []
        var n = 1
        if p.buildDays > 1 {
            for d in 1..<p.buildDays {
                let date = p.startDate.adding(days: d)
                let wd = cal.component(.weekday, from: date)
                if weekdayMask & (1 << (wd - 1)) != 0 {
                    out.append(Milestone(title: "Checkpoint \(n)", dueDate: date))
                    n += 1
                }
            }
        }
        out.append(Milestone(title: "Ship it! 🚀", dueDate: p.startDate.adding(days: max(p.buildDays - 1, 0)), isLaunch: true))
        out.append(Milestone(title: "Traction review", dueDate: p.observeEnd.adding(days: -1)))
        return out
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

    // MARK: Completing & missing

    @discardableResult
    static func complete(_ m: Milestone, profile: Profile, celebration: CelebrationCenter) -> Int {
        guard !m.isDone else { return 0 }
        let onTime = Date.now.startOfDay <= m.dueDate
        let oldLevel = profile.level
        m.completedAt = .now
        Notifier.cancel(m)

        let gained: Int
        if onTime {
            gained = m.isLaunch ? 50 : 10
            profile.streak += 1
            profile.bestStreak = max(profile.bestStreak, profile.streak)
        } else {
            gained = 3
        }
        profile.xp += gained

        if profile.level > oldLevel {
            celebration.fire(title: "Level \(profile.level)! 🎉", subtitle: "+\(gained) XP · You're on a roll")
        } else if onTime {
            celebration.fire(title: "+\(gained) XP", subtitle: "\(praise()) 🔥 \(profile.streak) on-time in a row")
        } else {
            celebration.fire(title: "+\(gained) XP", subtitle: "Late is better than never. Keep going!", confetti: false)
        }
        return gained
    }

    /// Flags deadlines that slipped past; resets the streak once per slip.
    @discardableResult
    static func evaluateMissed(projects: [Project], profile: Profile) -> Int {
        var count = 0
        for m in projects.flatMap({ $0.milestones ?? [] }) where m.isOverdue && !m.missed {
            m.missed = true
            count += 1
        }
        if count > 0 { profile.streak = 0 }
        return count
    }

    static func praise() -> String {
        ["Nailed it!", "Right on time!", "Look at you go!", "Shipping machine!", "Crushing it!", "That's the spirit!"].randomElement()!
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
        add(m.id.uuidString, hour: hour, title: "\(project.emoji) Deadline day!",
            body: "\(m.title) for \(project.name) is due today. You've got this!")
        add(m.id.uuidString + "-pm", hour: 18, title: "Still time today ⏰",
            body: "\(m.title) · \(project.name). Finish it and keep your streak alive!")
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
