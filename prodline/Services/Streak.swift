import Foundation

/// The streak counts days, Duolingo style: a day counts when something moved in any project
/// (a goal or checkpoint finished, or a commit to a linked repo). Today keeps the streak alive
/// until midnight, so a streak only breaks after a whole day without progress.
enum Streak {
    /// Every day with progress, across all projects.
    static func activeDays(_ projects: [Project]) -> Set<Date> {
        var days = Set<Date>()
        for p in projects {
            for m in p.milestones ?? [] {
                if let done = m.completedAt { days.insert(done.startOfDay) }
                for g in m.goals ?? [] where g.isDone {
                    if let at = g.doneAt { days.insert(at.startOfDay) }
                }
            }
            for (key, n) in p.commitDays where n > 0 {
                if let d = Momentum.date(fromKey: key) { days.insert(d) }
            }
        }
        return days
    }

    /// Consecutive active days ending today, or ending yesterday while today is still open.
    static func current(_ days: Set<Date>, now: Date = .now) -> Int {
        var d = now.startOfDay
        if !days.contains(d) { d = d.adding(days: -1) }
        var n = 0
        while days.contains(d) { n += 1; d = d.adding(days: -1) }
        return n
    }

    /// Longest run of consecutive active days.
    static func longest(_ days: Set<Date>) -> Int {
        var best = 0
        for d in days where !days.contains(d.adding(days: -1)) {
            var n = 1
            var next = d.adding(days: 1)
            while days.contains(next) { n += 1; next = next.adding(days: 1) }
            best = max(best, n)
        }
        return best
    }

    /// Recomputes the profile's streak from the data. Returns true if today already counts.
    @discardableResult
    static func update(_ profile: Profile, projects: [Project], now: Date = .now) -> Bool {
        let days = activeDays(projects)
        profile.streak = current(days, now: now)
        profile.bestStreak = max(profile.bestStreak, longest(days))
        let today = days.contains(now.startOfDay)
        profile.streakActiveToday = today ? now.startOfDay : profile.streakActiveToday
        return today
    }

    /// `update`, plus the moment it matters: today's first progress lights the flame on screen.
    @MainActor
    static func refresh(_ profile: Profile, projects: [Project], celebration: CelebrationCenter?, now: Date = .now) {
        let wasLit = isActiveToday(profile, now: now)
        update(profile, projects: projects, now: now)
        if !wasLit, isActiveToday(profile, now: now), profile.streak > 0 {
            celebration?.lightStreak(profile.streak)
        }
    }

    static func isActiveToday(_ profile: Profile, now: Date = .now) -> Bool {
        profile.streakActiveToday == now.startOfDay
    }
}
