import SwiftUI

/// Something that happened in a project: a goal or checkpoint done, a number that moved, a phase that
/// began. The Mac dashboard lists the latest ones so it reads like a status update.
struct ActivityItem: Identifiable {
    let id: String
    let date: Date
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    /// Newest first, from the last two weeks.
    static func make(projects: [Project], refresher: DataRefresher, now: Date = .now) -> [ActivityItem] {
        let since = now.startOfDay.adding(days: -14)
        var items: [ActivityItem] = []
        for p in projects {
            let accent = p.accent.text
            for m in p.sortedMilestones {
                // Goals ticked the same day in one checkpoint read as one line, not a burst of them.
                let done = (m.goals ?? []).filter { $0.isDone && ($0.doneAt ?? .distantPast) >= since }
                for (day, gs) in Dictionary(grouping: done, by: { $0.doneAt!.startOfDay }) {
                    let last = gs.map { $0.doneAt! }.max()!
                    if gs.count >= 3 {
                        items.append(.init(id: "goals-\(m.id)-\(day)", date: last, symbol: "checklist.checked", tint: accent,
                                           title: "\(gs.count) goals done", detail: "\(p.name) · \(m.title)"))
                    } else {
                        for g in gs {
                            let by = g.source == .manual || g.source == .ai ? "" : " · via \(g.source.shortName)"
                            items.append(.init(id: "goal-\(g.id)", date: g.doneAt!, symbol: "checkmark", tint: accent,
                                               title: g.title, detail: "\(p.name)\(by)"))
                        }
                    }
                }
                if let at = m.completedAt, at >= since {
                    items.append(.init(id: "cp-\(m.id)", date: at, symbol: "flag.checkered", tint: Theme.success,
                                       title: "\(m.title) done", detail: "\(p.name) · \(m.completedOnTime ? "on time" : "late")"))
                } else if m.isOverdue, m.dueDate >= since {
                    items.append(.init(id: "late-\(m.id)", date: m.dueDate.adding(days: 1), symbol: "exclamationmark", tint: Theme.danger,
                                       title: "\(m.title) is overdue", detail: p.name))
                }
            }
            if p.startDate >= since, p.startDate <= now {
                items.append(.init(id: "start-\(p.id)", date: p.startDate, symbol: "hammer.fill", tint: accent,
                                   title: "Started building", detail: p.name))
            }
            if p.buildEnd >= since, p.buildEnd <= now {
                items.append(.init(id: "launch-\(p.id)", date: p.buildEnd, symbol: "paperplane.fill", tint: accent,
                                   title: "Launched, now observing", detail: p.name))
            }
            if let at = p.verdictAt, at >= since, let v = p.verdict {
                items.append(.init(id: "verdict-\(p.id)", date: at, symbol: v.symbol, tint: Accent(hex: v.hex).text,
                                   title: v.pastTense, detail: p.name))
            }
            items += metricMoves(p, refresher: refresher, now: now)
        }
        return items.sorted { $0.date > $1.date }
    }

    /// How the project's shown numbers moved today, against the last reading before midnight: one line per
    /// project, so a few busy services don't push everything else out.
    private static func metricMoves(_ p: Project, refresher: DataRefresher, now: Date) -> [ActivityItem] {
        let snaps = p.sortedSnapshots
        let today = now.startOfDay
        var latestAt = Date.distantPast
        let moves: [String] = refresher.shownMetrics(for: p).compactMap { key in
            guard let latest = snaps.last(where: { $0.valueIfPresent(key) != nil }), latest.date >= today,
                  let base = snaps.last(where: { $0.date < today && $0.valueIfPresent(key) != nil })?.valueIfPresent(key),
                  let value = latest.valueIfPresent(key), value > base else { return nil }
            latestAt = max(latestAt, latest.date)
            return "+\(Stat.format(key, value - base)) \(Stat.title(key).lowercased())"
        }
        guard !moves.isEmpty else { return [] }
        return [ActivityItem(id: "metrics-\(p.id)", date: latestAt, symbol: "chart.line.uptrend.xyaxis", tint: p.accent.text,
                             title: "\(moves[0]) today",
                             detail: ([p.name] + [moves.dropFirst().joined(separator: ", ")].filter { !$0.isEmpty }).joined(separator: " · "))]
    }
}

/// The dashboard's status panel: what happened lately, grouped by day.
struct MacActivityPanel: View {
    let projects: [Project]
    var limit = 9
    @Environment(DataRefresher.self) private var refresher

    var body: some View {
        let items = Array(ActivityItem.make(projects: projects, refresher: refresher).prefix(limit))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").cardTitle(20).foregroundStyle(Theme.ink)
                Spacer()
                Text("Last 2 weeks").eyebrow(size: 10)
            }
            if items.isEmpty {
                Text("Goals you finish and numbers that move show up here.")
                    .font(.ui(13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i == 0 || !Calendar.current.isDate(item.date, inSameDayAs: items[i - 1].date) {
                            Text(dayLabel(item.date)).eyebrow(size: 10)
                                .padding(.top, i == 0 ? 0 : 12).padding(.bottom, 6)
                        }
                        row(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 20, radius: 24)
    }

    private func row(_ item: ActivityItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(item.tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(item.tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.ui(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(item.detail).font(.ui(12)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(time(item.date)).font(.ui(11, .medium)).foregroundStyle(Theme.tertiary).monospacedDigit()
                .padding(.top, 1)
        }
        .padding(.vertical, 5)
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// Clock time when there is one; days that only carry a date (a phase starting) show none.
    private func time(_ d: Date) -> String {
        d == d.startOfDay ? "" : d.formatted(.dateTime.hour().minute())
    }
}
