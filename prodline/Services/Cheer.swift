import Foundation
import UserNotifications

/// Push notifications for wins that happen while the app isn't open: a goal ticked by a push to GitHub,
/// a checkpoint completing, a level up, the streak catching. On screen the in-app banners do this job,
/// so nothing is sent while the app is in front.
enum Cheer {
    /// Set by the UI while a scene is active; background launches (relay pushes, refreshes) leave it off.
    nonisolated(unsafe) static var appIsOpen = false

    static var enabled: Bool { !appIsOpen && AppSettings.cheers && !isTesting }
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    // MARK: Goals

    struct DoneGoal { let title: String; let project: String; let late: Bool }

    static func goals(_ goals: [DoneGoal], xp: Int) {
        guard enabled, let first = goals.first else { return }
        let lines: (String, String)
        if goals.count == 1 {
            lines = first.late ? lateGoal(first, xp: xp) : goal(first, xp: xp)
        } else {
            let projects = Set(goals.map(\.project))
            let place = projects.count == 1 ? first.project : "\(projects.count) projects"
            lines = pick([
                ("\(goals.count) goals off the list 🧹", "That's +\(xp) XP in \(place). Someone's in the zone."),
                ("\(goals.count) goals, one push 💥", "\(place) just moved. +\(xp) XP."),
                ("Combo! \(goals.count) goals done", "+\(xp) XP in \(place). Keep the streak warm."),
            ], seed: goals.count + xp)
        }
        post(id: "goals-\(UUID().uuidString)", title: lines.0, body: lines.1, thread: first.project)
    }

    private static func goal(_ g: DoneGoal, xp: Int) -> (String, String) {
        pick([
            ("“\(g.title)” done ✅", "That's +\(xp) XP. \(g.project) thanks you."),
            ("Off the list: \(g.title)", "Nice one. +\(xp) XP for \(g.project)."),
            ("\(g.title) ✔︎", "Ticked by your last push. +\(xp) XP, zero clicks."),
            ("Boom. \(g.title)", "+\(xp) XP. \(g.project) is one step closer to shipping."),
            ("\(g.title): handled", "+\(xp) XP. Small wins, big projects."),
        ], seed: g.title.count)
    }

    private static func lateGoal(_ g: DoneGoal, xp: Int) -> (String, String) {
        pick([
            ("\(g.title)… finally 🐢", "Took you quite some time, huh? +\(xp) XP anyway."),
            ("Look who showed up: \(g.title)", "Fashionably late. Still +\(xp) XP."),
            ("\(g.title) done (eventually)", "The deadline sends its regards. +\(xp) XP."),
            ("Better late than never ✅", "\(g.title) is off the list. +\(xp) XP."),
        ], seed: g.title.count)
    }

    // MARK: Checkpoints

    static func checkpoint(title: String, project: String, xp: Int, daysEarly: Int, isLaunch: Bool, level: Int?) {
        guard enabled else { return }
        let lines: (String, String)
        if let level {
            lines = ("Level \(level) 🎉", "\(title) in \(project) pushed you over. +\(xp) XP.")
        } else if isLaunch && daysEarly >= 0 {
            lines = pick([
                ("\(project) shipped 🚀", daysEarly > 0 ? "\(daysEarly) day\(daysEarly == 1 ? "" : "s") early. Go tell someone. +\(xp) XP." : "Right on time. +\(xp) XP. Now watch the numbers."),
                ("It's out there: \(project) 🚀", "Launch done. +\(xp) XP. The observe phase starts now."),
            ], seed: xp)
        } else if daysEarly < 0 {
            let late = -daysEarly
            lines = pick([
                ("\(title): done, \(late) day\(late == 1 ? "" : "s") late", "Better late than never. +\(xp) XP."),
                ("\(title) finally crossed the line 🐢", "\(late) day\(late == 1 ? "" : "s") over, but who's counting? (Us. +\(xp) XP.)"),
            ], seed: late)
        } else if daysEarly > 0 {
            lines = pick([
                ("\(title) done early 😎", "\(daysEarly) day\(daysEarly == 1 ? "" : "s") to spare in \(project). +\(xp) XP."),
                ("Ahead of schedule: \(title)", "\(project) is flying. +\(xp) XP."),
            ], seed: daysEarly)
        } else {
            lines = pick([
                ("\(title) complete 🎯", "Right on time. +\(xp) XP for \(project)."),
                ("Checkpoint cleared: \(title)", "Deadline met, \(project) moving. +\(xp) XP."),
            ], seed: xp)
        }
        post(id: "checkpoint-\(UUID().uuidString)", title: lines.0, body: lines.1, thread: project)
    }

    // MARK: Streak

    static func streak(_ days: Int) {
        guard enabled, days > 0 else { return }
        let lines = days == 1
            ? ("🔥 Streak started", "Day 1. Every streak starts somewhere.")
            : pick([("🔥 \(days)-day streak", "Today counts. The flame is happy."),
                    ("🔥 Day \(days), lit", "You showed up again. That's the whole trick.")], seed: days)
        post(id: "streak-\(UUID().uuidString)", title: lines.0, body: lines.1, thread: "streak")
        // Today counts now: the "ends tonight" nudge isn't needed.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [StreakNudge.id(0)])
    }

    // MARK: Plumbing

    /// A stable pick for the same input, a different one for the next win.
    private static func pick(_ options: [(String, String)], seed: Int) -> (String, String) {
        let counter = UserDefaults.standard.integer(forKey: "cheer.counter") + 1
        UserDefaults.standard.set(counter, forKey: "cheer.counter")
        return options[abs(seed &+ counter) % options.count]
    }

    private static func post(id: String, title: String, body: String, thread: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        content.relevanceScore = 0.6
        // A moment later, so several wins from one sync arrive in a sensible order.
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
