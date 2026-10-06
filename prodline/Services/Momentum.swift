import Foundation

/// Build-phase stats: is the project moving? Commits per day, goals done and how many days saw work.
/// Once a project ships, traction (visits, social views, revenue) takes over.
struct Momentum {
    struct Day: Identifiable {
        let date: Date
        let commits: Int
        let goalsDone: Int        // cumulative
        let goalsFinished: Int    // finished that day
        var id: Date { date }
        /// Something moved that day: a commit or a finished goal (so it works without a repo too).
        var isActive: Bool { commits > 0 || goalsFinished > 0 }
    }

    /// Build days from the start up to today (later build days are left out).
    let days: [Day]
    /// All build days, for the active-days strip (future ones are drawn empty).
    let buildLength: Int
    /// False when neither a linked repo nor the project's API reports commits.
    let hasCommitData: Bool
    let goalsDone: Int
    let goalsTotal: Int

    var commitsToday: Int { days.last?.commits ?? 0 }
    var totalCommits: Int { days.reduce(0) { $0 + $1.commits } }
    var activeDays: Int { days.filter(\.isActive).count }
    var elapsedDays: Int { days.count }

    static func make(project p: Project, now: Date = .now) -> Momentum {
        let today = now.startOfDay
        let buildLength = max(1, Date.days(from: p.startDate, to: p.buildEnd))
        let elapsed = min(buildLength, max(0, Date.days(from: p.startDate, to: today) + 1))

        // Commits: the linked repo first, else a cumulative "commits" number from the project's API.
        var perDay: [String: Int] = p.commitDays
        var hasData = !p.githubRepo.isEmpty || !perDay.isEmpty
        if perDay.isEmpty {
            let fromAPI = apiDailyCommits(p.sortedSnapshots)
            if !fromAPI.isEmpty { perDay = fromAPI; hasData = true }
        }

        let goals = p.sortedMilestones.filter { $0.dueDate <= p.buildEnd || $0.isLaunch }.flatMap { $0.goals ?? [] }
        let doneDates = goals.compactMap { $0.isDone ? ($0.doneAt ?? now) : nil }

        let days = (0..<elapsed).map { i -> Day in
            let d = p.startDate.adding(days: i)
            let end = d.adding(days: 1)
            return Day(date: d, commits: perDay[key(d)] ?? 0, goalsDone: doneDates.filter { $0 < end }.count,
                       goalsFinished: doneDates.filter { $0 >= d && $0 < end }.count)
        }
        return Momentum(days: days, buildLength: buildLength, hasCommitData: hasData,
                        goalsDone: goals.filter(\.isDone).count, goalsTotal: goals.count)
    }

    // MARK: Helpers

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }
    static func date(fromKey key: String) -> Date? { keyFormatter.date(from: key)?.startOfDay }

    /// Commit times → commits per local day.
    static func dailyCounts(_ dates: [Date]) -> [String: Int] {
        var out: [String: Int] = [:]
        for d in dates { out[key(d), default: 0] += 1 }
        return out
    }

    /// A cumulative "commits" extra from the API (like Prodline's own feed) → commits per day.
    static func apiDailyCommits(_ snapshots: [MetricSnapshot]) -> [String: Int] {
        var endOfDay: [String: Double] = [:]
        for s in snapshots { if let c = s.extras["commits"] { endOfDay[key(s.date)] = c } }
        let keys = endOfDay.keys.sorted()
        var out: [String: Int] = [:]
        for (i, k) in keys.enumerated() where i > 0 {
            out[k] = max(0, Int(endOfDay[k]! - endOfDay[keys[i - 1]]!))
        }
        return out
    }
}
