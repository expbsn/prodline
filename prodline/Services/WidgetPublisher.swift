import Foundation
import UIKit
import WidgetKit

/// Turns the app's projects into the small JSON the widgets read (Shared/WidgetData.swift),
/// and reloads widget timelines only when something visible actually changed.
enum WidgetPublisher {
    static func publish(projects: [Project], profile: Profile?, refresher: DataRefresher, now: Date = .now) {
        let data = WidgetData(generatedAt: now, streak: profile?.streak ?? 0,
                              projects: projects.sorted { $0.startDate < $1.startDate }.map { make($0, refresher: refresher, now: now) })
        var covers: [String: Data] = [:]
        for p in projects {
            if let img = p.cover, let jpeg = ImageTools.squareJPEG(img, side: 240) { covers[p.id.uuidString] = jpeg }
        }
        let coversChanged = SharedStore.writeCovers(covers)
        let dataChanged = SharedStore.write(data)
        if coversChanged || dataChanged { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Goals ticked on the home screen since the app last ran. Returns true if anything changed;
    /// the usual pass (GoalEngine.afterRefresh) then pays the XP and finishes checkpoints.
    @discardableResult
    static func applyWidgetTicks(projects: [Project], profile: Profile?) -> Bool {
        let ticks = WidgetTicks.take()
        guard !ticks.isEmpty else { return false }
        var goals: [String: Goal] = [:]
        for p in projects {
            for m in p.milestones ?? [] {
                for g in m.goals ?? [] { goals[g.id.uuidString] = g }
            }
        }
        var changed = false
        for tick in ticks {
            guard let g = goals[tick.goalID], !g.source.isAutomatic, g.isDone != tick.done else { continue }
            g.setDone(tick.done, at: tick.at)
            // Same as unticking in the app: a finished checkpoint with an open goal reopens.
            if !tick.done, let m = g.milestone, m.isDone, let profile { ScheduleEngine.uncomplete(m, profile: profile) }
            changed = true
        }
        return changed
    }

    static func make(_ p: Project, refresher: DataRefresher, now: Date) -> WidgetProject {
        let checkpoints = p.sortedMilestones.map { m in
            // Open ones first, so the five the widget gets are the ones that still matter.
            let goals = m.displayGoals
            return WidgetCheckpoint(title: m.title, due: m.dueDate, done: m.isDone, isLaunch: m.isLaunch,
                                    goals: goals.prefix(5).map { WidgetGoal(title: $0.title, done: $0.isDone, id: $0.id.uuidString,
                                                                              tickable: !$0.source.isAutomatic) },
                                    goalCount: goals.count, goalsDone: goals.filter(\.isDone).count)
        }
        let metrics: [WidgetMetric] = MetricKey.allCases.compactMap { key in
            guard let value = refresher.value(key, for: p) else { return nil }
            let spark = dailySeries(p, key: key, current: value, now: now)
            let weekAgo = spark.first ?? value
            let change = value - weekAgo
            return WidgetMetric(key: key.rawValue, title: key.title, symbol: key.symbol, value: value,
                                formatted: key.format(value),
                                delta: spark.count > 1 ? (change >= 0 ? "+" : "−") + key.format(abs(change)) : nil,
                                deltaPositive: change > 0, spark: spark)
        }
        var momentum: WidgetMomentum?
        if p.phase(on: now) == .building || p.phase(on: now) == .upcoming {
            let m = Momentum.make(project: p, now: now)
            momentum = WidgetMomentum(totalCommits: m.hasCommitData ? m.totalCommits : nil,
                                      commitsToday: m.hasCommitData ? m.commitsToday : nil,
                                      dailyCommits: m.days.suffix(14).map(\.commits),
                                      activeDays: m.activeDays, elapsedDays: m.elapsedDays,
                                      goalsDone: m.goalsDone, goalsTotal: m.goalsTotal)
        }
        return WidgetProject(id: p.id.uuidString, name: p.name, accentHex: p.accentHex,
                             startDate: p.startDate, buildEnd: p.buildEnd, observeEnd: p.observeEnd,
                             checkpoints: checkpoints, metrics: metrics, momentum: momentum)
    }

    /// End-of-day values for the last 7 days (oldest first), ending with the live value.
    static func dailySeries(_ p: Project, key: MetricKey, current: Double, now: Date) -> [Double] {
        let snaps = p.sortedSnapshots
        guard !snaps.isEmpty else { return [current] }
        var out: [Double] = []
        var i = 0
        var last: Double?
        for back in stride(from: 6, through: 1, by: -1) {
            let end = now.startOfDay.adding(days: 1 - back)
            while i < snaps.count, snaps[i].date < end { last = snaps[i].value(key); i += 1 }
            out.append(last ?? 0)
        }
        out.append(current)
        // Drop leading days before the project had any numbers so the line doesn't start with a cliff.
        while out.count > 2, out[0] == 0, out[1] == 0 { out.removeFirst() }
        return out
    }
}
