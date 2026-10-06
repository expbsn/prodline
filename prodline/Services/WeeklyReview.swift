import Foundation
import UserNotifications

/// A week of work, summed up for the Sunday-evening review.
struct WeekStats {
    struct ProjectWeek: Identifiable {
        let project: Project
        let goals: Int
        let commits: Int
        var id: UUID { project.id }
        var score: Int { goals * 3 + commits }
    }

    struct Upcoming: Identifiable {
        let title: String
        let project: String
        let accent: Accent
        let due: Date
        let id = UUID()
    }

    let week: Int
    let year: Int
    let start: Date
    /// Mon…Sun.
    let days: [Date]
    let active: [Bool]
    let xp: Int
    let goalsDone: Int
    let goalTitles: [(String, Accent)]
    let checkpointsOnTime: Int
    let checkpointsLate: Int
    let slipped: Int
    let commits: [Int]
    let visitsGained: Double
    let revenueGained: Double
    let projectOfWeek: ProjectWeek?
    let upcoming: [Upcoming]
    let streak: Int

    var activeCount: Int { active.filter { $0 }.count }
    var totalCommits: Int { commits.reduce(0, +) }
    var busiestDay: Int? {
        guard let m = commits.max(), m > 0 else { return nil }
        return commits.firstIndex(of: m)
    }
    var end: Date { start.adding(days: 7) }
    var key: String { "\(year)-\(week)" }
    var range: String {
        let last = start.adding(days: 6)
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

enum WeeklyReview {
    static let hour = 18
    static let weekday = 1 // Sunday
    static let notificationID = "weekly-review"
    static let watchedKey = "review.watched"
    /// Posted to show the latest review (Me, notification taps).
    static let open = Notification.Name("WeeklyReview.open")

    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    /// Monday of the week the latest review covers: this week from Sunday 18:00 on, otherwise last week.
    static func reviewWeekStart(now: Date = .now) -> Date {
        let cal = calendar
        let monday = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now.startOfDay
        let sundayEvening = cal.date(byAdding: .hour, value: 6 * 24 + hour, to: monday) ?? now
        return now >= sundayEvening ? monday : cal.date(byAdding: .day, value: -7, to: monday) ?? monday
    }

    static func isWatched(_ start: Date, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: watchedKey) == key(start)
    }

    static func markWatched(_ start: Date, defaults: UserDefaults = .standard) {
        defaults.set(key(start), forKey: watchedKey)
    }

    static func key(_ start: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    /// Fresh review waiting on Dash: from Sunday 18:00 until it's watched, for three days at most.
    static func isWaiting(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        let start = reviewWeekStart(now: now)
        #if DEBUG
        // -PRODLINE_REVIEW_READY YES: pretend it's Sunday evening.
        if defaults.bool(forKey: "PRODLINE_REVIEW_READY") { return !isWatched(start, defaults: defaults) }
        #endif
        let ready = calendar.date(byAdding: .hour, value: 6 * 24 + hour, to: start) ?? now
        return now >= ready && now < ready.addingTimeInterval(3 * 86_400) && !isWatched(start, defaults: defaults)
    }

    static func make(projects: [Project], profile: Profile, weekStart: Date, now: Date = .now) -> WeekStats {
        let cal = calendar
        let days = (0..<7).map { weekStart.adding(days: $0) }
        let end = weekStart.adding(days: 7)
        func inWeek(_ d: Date?) -> Bool { d.map { $0 >= weekStart && $0 < end } ?? false }

        let activeSet = Streak.activeDays(projects)
        var xp = 0, goalsDone = 0, onTime = 0, late = 0, slipped = 0
        var titles: [(String, Accent)] = []
        var commits = Array(repeating: 0, count: 7)
        var perProject: [Project.ID: (goals: Int, commits: Int)] = [:]
        var visits = 0.0, revenue = 0.0

        for p in projects {
            for m in p.milestones ?? [] {
                if inWeek(m.completedAt) {
                    xp += m.xpEarned
                    if m.completedOnTime { onTime += 1 } else { late += 1 }
                }
                if inWeek(m.dueDate), !m.completedOnTime, m.dueDate < now.startOfDay { slipped += 1 }
                for g in m.goals ?? [] where g.isDone && inWeek(g.doneAt) {
                    xp += g.xpPaid
                    goalsDone += 1
                    titles.append((g.title, p.accent))
                    perProject[p.id, default: (0, 0)].goals += 1
                }
            }
            if inWeek(p.verdictAt), p.verdict != nil { xp += VerdictEngine.xp }
            let cd = p.commitDays
            for (i, d) in days.enumerated() {
                let n = cd[Momentum.key(d)] ?? 0
                commits[i] += n
                perProject[p.id, default: (0, 0)].commits += n
            }
            // Traction gained over the week, from stored snapshots.
            let snaps = p.sortedSnapshots
            let before = snaps.last { $0.date < weekStart }
            if let after = snaps.last(where: { $0.date < end }), after.date >= weekStart {
                visits += max(0, after.visits - (before?.visits ?? 0))
                revenue += max(0, after.revenue - (before?.revenue ?? 0))
            }
        }

        let best = projects.compactMap { p -> WeekStats.ProjectWeek? in
            guard let s = perProject[p.id], s.goals + s.commits > 0 else { return nil }
            return .init(project: p, goals: s.goals, commits: s.commits)
        }.max { $0.score < $1.score }

        let next = projects.flatMap { p in
            (p.milestones ?? []).filter { !$0.isDone && $0.dueDate >= end && $0.dueDate < end.adding(days: 7) }
                .map { WeekStats.Upcoming(title: $0.title, project: p.name, accent: p.accent, due: $0.dueDate) }
        }.sorted { $0.due < $1.due }

        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
        return WeekStats(week: comps.weekOfYear ?? 0, year: comps.yearForWeekOfYear ?? 0, start: weekStart, days: days,
                         active: days.map { activeSet.contains($0) }, xp: xp, goalsDone: goalsDone, goalTitles: titles,
                         checkpointsOnTime: onTime, checkpointsLate: late, slipped: slipped, commits: commits,
                         visitsGained: visits, revenueGained: revenue, projectOfWeek: best, upcoming: next, streak: profile.streak)
    }

    /// Every Sunday at 18:00.
    static func scheduleNotification(enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your weekly review is ready 🎬"
        content.body = "A quick look back at your week, and what's next. Takes a minute."
        content.sound = .default
        content.userInfo = ["url": "prodline://review"]
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        center.add(UNNotificationRequest(identifier: notificationID, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}

/// The lines in the review: a few per situation, picked by the week so they rotate and don't repeat in one story.
struct ReviewCopy {
    let stats: WeekStats
    private var seed: Int { stats.year * 53 + stats.week }

    private func pick(_ lines: [String], _ salt: Int) -> String {
        lines[abs(seed &* 31 &+ salt) % lines.count]
    }

    private func s(_ n: Int) -> String { n == 1 ? "" : "s" }

    var intro: String {
        pick(["Week \(stats.week) is in the books. Let's open them.",
              "Week \(stats.week). Grab a coffee, this one's about you.",
              "Week \(stats.week), reviewed. No pressure. Some pressure."], 1)
    }

    var activeDays: String {
        let n = stats.activeCount
        switch n {
        case 7: return pick(["Seven for seven. Do you sleep?", "Every single day. Your projects feel very seen."], 2)
        case 5...6: return pick(["\(n) out of 7. Basically a machine with weekends.", "\(n) active days. Consistency looks good on you."], 2)
        case 3...4: return pick(["\(n) days of progress. Solid, with room for a sequel.", "\(n) active days. Half the week, all of the vibes."], 2)
        case 1...2: return pick(["\(n) active day\(s(n)). Quality over quantity, right?", "\(n) day\(s(n)) on the board. Comebacks start small."], 2)
        default: return pick(["Zero active days. Your projects filed a missing person report.", "A quiet week. Even legends take breaks. Short ones."], 2)
        }
    }

    var xp: String {
        let x = stats.xp
        switch x {
        case 100...: return pick(["+\(x) XP. Somebody's leveling up.", "+\(x) XP. The XP bar needed a bigger bar."], 3)
        case 30..<100: return pick(["+\(x) XP. Real progress, not just vibes.", "+\(x) XP. That's a week with receipts."], 3)
        case 1..<30: return pick(["+\(x) XP. Small steps still count. They literally do, we checked.", "+\(x) XP. Warming up nicely."], 3)
        default: return pick(["No XP this week. The XP misses you. It told us.", "0 XP. Plot twist incoming next week?"], 3)
        }
    }

    var goals: String {
        let g = stats.goalsDone, late = stats.checkpointsLate, slipped = stats.slipped
        var line: String
        switch g {
        case 0: line = pick(["No goals ticked. They're still there. Waiting. Patiently.", "Goals done: 0. Suspense is a strategy too."], 4)
        case 1...3: line = pick(["\(g) goal\(s(g)) done. Every list starts shrinking somewhere.", "\(g) goal\(s(g)) ticked. Chipping away."], 4)
        default: line = pick(["\(g) goals done. Your to-do list is shrinking in fear.", "\(g) goals ticked. Somebody's on a roll."], 4)
        }
        if slipped > 0 { line += pick([" \(slipped) deadline\(s(slipped)) slipped. We saw that. We're not mad.", " \(slipped) deadline\(s(slipped)) got away. It happens."], 5) }
        else if late > 0 { line += " \(late) checkpoint\(s(late)) arrived fashionably late." }
        return line
    }

    var commits: String {
        let n = stats.totalCommits
        guard let i = stats.busiestDay else { return "No commits this week. The repo is enjoying the silence." }
        let day = stats.days[i].formatted(.dateTime.weekday(.wide))
        let top = stats.commits[i]
        return n >= 15
            ? pick(["\(day) you pushed \(top) commits. \(day)-you is the real MVP.", "\(n) commits. The keyboard would like a word."], 6)
            : pick(["\(n) commit\(s(n)), each one hand-crafted. \(day) did the heavy lifting.", "\(n) commit\(s(n)) this week. Steady hands."], 6)
    }

    var traction: String {
        if stats.revenueGained > 0 {
            return pick(["+\(MetricKey.money(stats.revenueGained)). Money came in. Act natural.", "+\(MetricKey.money(stats.revenueGained)) this week. Someone paid for your thing!"], 7)
        }
        return pick(["+\(MetricKey.count(stats.visitsGained)) visits. People are actually showing up.", "+\(MetricKey.count(stats.visitsGained)) visits. The internet noticed."], 7)
    }

    func projectOfWeek(_ name: String) -> String {
        pick(["\(name) got the most love this week.", "\(name) was the favorite. Don't tell the others."], 8)
    }

    var next: String {
        if let first = stats.upcoming.first {
            let k = stats.upcoming.count
            return "\(k) checkpoint\(s(k)) next week. First up: \(first.title) on \(first.due.formatted(.dateTime.weekday(.wide)))."
        }
        return "A free week ahead. Suspiciously free. Maybe start something from the idea inbox?"
    }

    var challenge: String {
        let target = min(7, max(3, stats.activeCount + 1))
        return stats.activeCount >= 7 ? "Challenge: do it all again. Yes, all seven." : "Challenge: \(target) active days next week."
    }

    var outro: String {
        pick(["See you next Sunday.", "Go make week \(stats.week + 1) a good one.", "That's a wrap. Proud of you, honestly."], 9)
    }
}
