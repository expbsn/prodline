import SwiftUI
import WidgetKit

// Widget layouts. Shared with the app so Me → Widgets can show exactly what lands on the home screen.

// MARK: - Pieces

/// The project letter on its accent, with the chunky 3D edge used for buttons in the app.
struct WBadge: View {
    let project: WidgetProject
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(project.accent.base)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(project.accent.dark).offset(y: size * 0.08))
            .overlay(Text(project.initial).display(size * 0.55, 800).foregroundStyle(project.accent.on))
            .frame(width: size, height: size)
    }
}

/// Thick progress ring with a tinted track.
struct WRing<Center: View>: View {
    let progress: Double
    let accent: Accent
    var width: CGFloat = 7
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(accent.base.opacity(0.15), lineWidth: width)
            Circle().trim(from: 0, to: max(0.001, progress))
                .stroke(AngularGradient(colors: [accent.base.opacity(0.75), accent.base], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
    }
}

/// Ring of short ticks, filled up to `progress`.
struct WTickRing: View {
    let progress: Double
    let accent: Accent
    var ticks = 36

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            ZStack {
                ForEach(0..<ticks, id: \.self) { i in
                    let on = Double(i) / Double(ticks) < progress
                    Capsule()
                        .fill(on ? accent.base : Theme.line)
                        .frame(width: r * 0.07, height: r * 0.2)
                        .offset(y: -r + r * 0.1)
                        .rotationEffect(.degrees(Double(i) / Double(ticks) * 360))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Smoothed line with a soft fill below.
struct WSparkline: View {
    let values: [Double]
    let color: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    area(pts, height: geo.size.height)
                        .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    line(pts).stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = max(hi - lo, 0.0001)
        return values.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: size.height - lineWidth - (size.height - 2 * lineWidth) * CGFloat((v - lo) / span))
        }
    }
    private func line(_ p: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: p[0])
        for i in 1..<p.count {
            let mid = CGPoint(x: (p[i - 1].x + p[i].x) / 2, y: (p[i - 1].y + p[i].y) / 2)
            path.addQuadCurve(to: mid, control: p[i - 1])
        }
        path.addLine(to: p[p.count - 1])
        return path
    }
    private func area(_ p: [CGPoint], height: CGFloat) -> Path {
        var path = line(p)
        path.addLine(to: CGPoint(x: p[p.count - 1].x, y: height))
        path.addLine(to: CGPoint(x: p[0].x, y: height))
        path.closeSubpath()
        return path
    }
}

/// One column of dots per day, lit up to that day's share of the busiest day.
struct WDotColumns: View {
    let values: [Double]
    let accent: Accent
    var rows = 7

    var body: some View {
        let hi = max(values.max() ?? 0, 0.0001)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(values.indices, id: \.self) { i in
                let lit = values[i] <= 0 ? 0 : max(1, Int((values[i] / hi * Double(rows)).rounded()))
                VStack(spacing: 3) {
                    ForEach(0..<rows, id: \.self) { r in
                        Circle()
                            .fill(rows - r <= lit ? accent.base : accent.base.opacity(0.12))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A miniature of the Dash card: cover photo (or big letter) fading into the accent, name on top.
struct WMiniCard: View {
    let project: WidgetProject
    let cover: UIImage?
    var date: Date = .now

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottomLeading) {
                project.accent.base
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                        .frame(width: w, height: w)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else {
                    Text(project.initial).display(w * 0.9, 900)
                        .foregroundStyle(project.accent.on.opacity(0.18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: w * 0.12, y: -w * 0.12)
                }
                // The photo is square (ends at 5/7 ≈ 0.71 of the height); be fully opaque before that edge
                // so it never shows as a seam, and ease in so the fade reads as one smooth wash.
                LinearGradient(stops: [.init(color: project.accent.base.opacity(0), location: 0.3),
                                       .init(color: project.accent.base.opacity(0.45), location: 0.48),
                                       .init(color: project.accent.base.opacity(0.85), location: 0.6),
                                       .init(color: project.accent.base, location: 0.68)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.phase(on: date).title).eyebrow(project.accent.on.opacity(0.8), size: max(7, w * 0.075))
                    Text(project.name).display(w * 0.17, 800).foregroundStyle(project.accent.on)
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                .padding(w * 0.09)
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.14, style: .continuous))
        }
    }
}

private struct GoalLine: View {
    let goal: WidgetGoal
    let accent: Accent
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().strokeBorder(goal.done ? accent.base : Theme.tertiary, lineWidth: 1.5)
                if goal.done {
                    Circle().fill(accent.base)
                    Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .heavy)).foregroundStyle(accent.on)
                }
            }
            .frame(width: size + 2, height: size + 2)
            Text(goal.title).font(.ui(size, .medium))
                .foregroundStyle(goal.done ? Theme.secondary : Theme.ink)
                .strikethrough(goal.done, color: Theme.tertiary)
                .lineLimit(1)
        }
    }
}

private struct DueChip: View {
    let checkpoint: WidgetCheckpoint
    let accent: Accent
    let date: Date

    var body: some View {
        let late = Date.days(from: date, to: checkpoint.due) < 0
        Text(checkpoint.dueText(from: date))
            .font(.ui(11, .bold))
            .foregroundStyle(late ? .white : accent.text)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(late ? Theme.danger : accent.base.opacity(0.14)))
    }
}

// MARK: - Project widget

struct ProjectWidgetView: View {
    let project: WidgetProject?
    let date: Date
    let family: WidgetFamily

    var body: some View {
        if let p = project {
            switch family {
            case .systemMedium: medium(p)
            case .systemLarge: large(p)
            case .accessoryCircular: circular(p)
            case .accessoryRectangular: rectangular(p)
            case .accessoryInline: inline(p)
            default: small(p)
            }
        } else {
            EmptyWidgetView(family: family)
        }
    }

    private func small(_ p: WidgetProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                WBadge(project: p, size: 24)
                Text(p.name).display(15, 750).foregroundStyle(Theme.ink).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let next = p.next(on: date) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.isLaunch ? "Launch" : "Next").eyebrow(size: 9)
                        Text(next.title).display(17, 750).foregroundStyle(Theme.ink)
                            .lineLimit(2).minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                    // Goals done when the checkpoint has goals, otherwise a countdown to it.
                    let days = max(0, Date.days(from: date, to: next.due))
                    WRing(progress: next.goalCount > 0 ? next.progress : max(0.04, 1 - Double(days) / 7), accent: p.accent, width: 5) {
                        if next.goalCount > 0 {
                            Text("\(next.goalsDone)/\(next.goalCount)").font(.ui(11, .bold)).foregroundStyle(Theme.ink)
                        } else {
                            VStack(spacing: -3) {
                                Text("\(days)").display(15, 800).foregroundStyle(Theme.ink)
                                Text(days == 1 ? "day" : "days").font(.ui(7, .bold)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                    .frame(width: 42, height: 42)
                }
                Spacer(minLength: 6)
                DueChip(checkpoint: next, accent: p.accent, date: date)
            } else {
                Text("Every checkpoint done").display(16, 750).foregroundStyle(Theme.ink)
                Spacer(minLength: 6)
                Text(p.phase(on: date).title).font(.ui(11, .bold)).foregroundStyle(p.accent.text)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(p.url)
    }

    private func medium(_ p: WidgetProject) -> some View {
        HStack(spacing: 14) {
            WMiniCard(project: p, cover: WidgetCovers.image(p.id), date: date)
                .aspectRatio(5 / 7, contentMode: .fit)
            VStack(alignment: .leading, spacing: 7) {
                if let next = p.next(on: date) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.title).display(18, 750).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        DueChip(checkpoint: next, accent: p.accent, date: date)
                    }
                    if next.goals.isEmpty {
                        Text(next.isLaunch ? "Launch day. Tick it off when it's out." : "No goals on this checkpoint.")
                            .font(.ui(13)).foregroundStyle(Theme.secondary).lineLimit(2)
                    }
                    goalList(next, max: 3, size: 13)
                } else {
                    Text("Every checkpoint done").display(18, 750).foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
                statsRow(p)
            }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        }
        .widgetURL(p.url)
    }

    private func large(_ p: WidgetProject) -> some View {
        let (day, of) = p.phaseDay(on: date)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                WMiniCard(project: p, cover: WidgetCovers.image(p.id), date: date)
                    .frame(width: 78, height: 109)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(p.phase(on: date).title) · day \(day) of \(of)").eyebrow(p.accent.text, size: 10)
                    Text(p.name).display(26, 800).foregroundStyle(Theme.ink).lineLimit(1)
                    timeline(p)
                    Text("\(p.doneCount) of \(p.checkpoints.count) deadlines done").font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
                }
            }
            if let next = p.next(on: date) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.title).display(19, 750).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        DueChip(checkpoint: next, accent: p.accent, date: date)
                    }
                    goalList(next, max: 3, size: 14)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if p.phase(on: date) == .building, let m = p.momentum {
                    tile(symbol: "chevron.left.forwardslash.chevron.right", value: m.totalCommits.map(String.init) ?? "–", label: "commits") {
                        if m.totalCommits != nil {
                            WSparkline(values: m.dailyCommits.map(Double.init), color: p.accent.base, lineWidth: 2)
                        } else {
                            Text("Link the repo").font(.ui(10, .medium)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    tile(symbol: "checkmark.circle.fill", value: "\(m.goalsDone)/\(m.goalsTotal)", label: "goals") {
                        progressBar(m.goalsTotal == 0 ? 0 : Double(m.goalsDone) / Double(m.goalsTotal), accent: p.accent)
                    }
                    tile(symbol: "flame.fill", value: "\(m.activeDays)/\(m.elapsedDays)", label: "active days") {
                        progressBar(m.elapsedDays == 0 ? 0 : Double(m.activeDays) / Double(m.elapsedDays), accent: p.accent)
                    }
                } else {
                    ForEach(p.metrics.prefix(3), id: \.key) { m in
                        tile(symbol: m.symbol, value: m.formatted, label: nil) {
                            WSparkline(values: m.spark, color: p.accent.base, lineWidth: 2)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .widgetURL(p.url)
    }

    /// The next checkpoint's goals, open ones first, capped with "+N more" so the layout never grows.
    @ViewBuilder
    private func goalList(_ next: WidgetCheckpoint, max: Int, size: CGFloat) -> some View {
        let ordered = next.goals.filter { !$0.done } + next.goals.filter(\.done)
        let shown = next.goalCount > max ? max - 1 : max
        ForEach(Array(ordered.prefix(shown).enumerated()), id: \.offset) { _, g in
            GoalLine(goal: g, accent: next.goals.isEmpty ? Accent.neutral : accentFor(next), size: size)
        }
        if next.goalCount > shown {
            Text("+\(next.goalCount - shown) more").font(.ui(size - 1, .semibold)).foregroundStyle(Theme.secondary)
        }
    }

    private func accentFor(_ c: WidgetCheckpoint) -> Accent { project?.accent ?? .neutral }

    /// While building: commits and active days; once shipped: visits and social views.
    @ViewBuilder
    private func statsRow(_ p: WidgetProject) -> some View {
        HStack(spacing: 12) {
            if p.phase(on: date) == .building, let m = p.momentum {
                if let commits = m.totalCommits {
                    Label("\(commits) commits", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Label("\(m.activeDays)/\(m.elapsedDays) active", systemImage: "flame.fill")
            } else {
                ForEach(p.metrics.prefix(2), id: \.key) { m in
                    Label(m.formatted, systemImage: m.symbol)
                }
            }
        }
        .font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }

    private func tile<Graph: View>(symbol: String, value: String, label: String?, @ViewBuilder graph: () -> Graph) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                if let label { Text(label).font(.ui(10, .semibold)).lineLimit(1) }
            }
            .foregroundStyle(Theme.secondary)
            Text(value).display(16, 750).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            graph().frame(height: 18)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.background))
    }

    private func progressBar(_ value: Double, accent: Accent) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.base.opacity(0.15))
                Capsule().fill(accent.base).frame(width: max(6, geo.size.width * min(1, value)))
            }
        }
        .frame(height: 6)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Build and observe bars with a marker for today, like the project screen.
    private func timeline(_ p: WidgetProject) -> some View {
        let total = max(1.0, p.observeEnd.timeIntervalSince(p.startDate))
        let buildFrac = p.buildEnd.timeIntervalSince(p.startDate) / total
        let now = min(1, max(0, date.timeIntervalSince(p.startDate) / total))
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    Capsule().fill(p.accent.base).frame(width: max(4, w * buildFrac - 1.5))
                    Capsule().fill(p.accent.base.opacity(0.25))
                }
                Capsule().fill(Theme.ink).frame(width: 3, height: 14).offset(x: w * now - 1.5)
            }
            .frame(height: 8)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
    }

    // Lock screen

    private func circular(_ p: WidgetProject) -> some View {
        let next = p.next(on: date)
        let days = next.map { max(0, Date.days(from: date, to: $0.due)) }
        return Gauge(value: next?.progress ?? p.phaseProgress(on: date)) {
            Text(p.initial)
        } currentValueLabel: {
            VStack(spacing: -2) {
                Text(days.map(String.init) ?? "✓").font(.system(size: 18, weight: .bold, design: .rounded))
                Text(days == nil ? "" : "days").font(.system(size: 8, weight: .semibold))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(p.url)
    }

    private func rectangular(_ p: WidgetProject) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(p.name).font(.system(size: 13, weight: .bold)).widgetAccentable()
            if let next = p.next(on: date) {
                Text(next.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(next.goalCount > 0 ? "\(next.dueText(from: date)) · \(next.goalsDone)/\(next.goalCount) goals" : next.dueText(from: date))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text("Every checkpoint done").font(.system(size: 15, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(p.url)
    }

    private func inline(_ p: WidgetProject) -> some View {
        if let next = p.next(on: date) {
            Text("\(p.name): \(next.title), \(next.dueText(from: date).lowercased())")
        } else {
            Text("\(p.name): all done")
        }
    }
}

// MARK: - Traction widget

struct TractionWidgetView: View {
    /// nil = all projects together.
    let project: WidgetProject?
    let projects: [WidgetProject]
    let metricKey: String
    let date: Date
    let family: WidgetFamily

    /// Combined metric across the shown projects.
    private var metric: WidgetMetric? {
        let ms = (project.map { [$0] } ?? projects).compactMap { $0.metric(metricKey) }
        guard let first = ms.first else { return nil }
        if ms.count == 1 { return first }
        // Sum the series aligned at their ends (today); shorter ones count as 0 before they start.
        let len = ms.map(\.spark.count).max() ?? 0
        var spark = [Double](repeating: 0, count: len)
        for m in ms {
            let offset = len - m.spark.count
            for (j, v) in m.spark.enumerated() { spark[offset + j] += v }
        }
        let value: Double = ms.reduce(0) { $0 + $1.value }
        let weekAgo: Double = spark.first ?? value
        let money = metricKey == "revenue"
        let sign = value >= weekAgo ? "+" : "−"
        let delta = sign + Self.format(abs(value - weekAgo), money: money)
        return WidgetMetric(key: first.key, title: first.title, symbol: first.symbol, value: value,
                            formatted: Self.format(value, money: money), delta: delta,
                            deltaPositive: value >= weekAgo, spark: spark)
    }

    private var accent: Accent { project?.accent ?? Accent(hex: 0x1C1C1E) }
    private var subtitle: String { project?.name ?? "All projects" }

    var body: some View {
        if let m = metric {
            switch family {
            case .systemMedium: medium(m)
            default: small(m)
            }
        } else {
            EmptyWidgetView(family: family, text: "No \(title.lowercased()) yet")
        }
    }

    private var title: String {
        switch metricKey {
        case "revenue": "Revenue"
        case "social_views": "Social views"
        default: "Visits"
        }
    }

    /// Like the "Energy Bank" tile: the project's color as the whole background.
    static func background(for project: WidgetProject?) -> some View {
        let a = project?.accent ?? Accent(hex: 0x1C1C1E)
        return LinearGradient(colors: [a.base, a.dark], startPoint: .top, endPoint: .bottom)
    }

    private func small(_ m: WidgetMetric) -> some View {
        let on = accent.on
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: m.symbol).font(.system(size: 12, weight: .bold))
                Text(m.title).eyebrow(on.opacity(0.85), size: 10)
            }
            .foregroundStyle(on.opacity(0.85))
            Text(subtitle).font(.ui(11, .medium)).foregroundStyle(on.opacity(0.7)).lineLimit(1)
            Spacer(minLength: 2)
            Text(m.formatted).display(32, 800).foregroundStyle(on)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let d = m.delta {
                Text("\(d) this week").font(.ui(11, .bold)).foregroundStyle(on)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(on.opacity(0.18)))
            }
            Spacer(minLength: 4)
            WSparkline(values: m.spark, color: on, lineWidth: 2.5).frame(height: 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "prodline://data/\(metricKey)"))
    }

    private func medium(_ m: WidgetMetric) -> some View {
        let daily = zip(m.spark.dropFirst(), m.spark).map { max(0, $0 - $1) }
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: m.symbol).font(.system(size: 12, weight: .bold))
                    Text(m.title).eyebrow(Theme.secondary, size: 10)
                }
                .foregroundStyle(Theme.secondary)
                Text(subtitle).font(.ui(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Text(m.formatted).display(34, 800).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let d = m.delta {
                    Text("\(d) this week").font(.ui(12, .bold))
                        .foregroundStyle(m.deltaPositive ? Theme.success : Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                WDotColumns(values: daily.isEmpty ? m.spark : daily, accent: accent.hex == 0x1C1C1E ? Accent(hex: 0x58CC02) : accent)
                HStack(spacing: 0) {
                    ForEach(weekdays(count: max(daily.count, 1)), id: \.self) { d in
                        Text(d).font(.ui(9, .semibold)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(width: 150)
        }
        .widgetURL(URL(string: "prodline://data/\(metricKey)"))
    }

    private func weekdays(count: Int) -> [String] {
        (0..<count).reversed().map { date.adding(days: -$0).formatted(.dateTime.weekday(.narrow)) + (count > 7 ? "\($0)" : "") }
    }

    static func format(_ v: Double, money: Bool) -> String {
        let compact = v >= 10_000
            ? v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
            : v.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
        return money ? "$" + compact : compact
    }
}

// MARK: - Lineup widget

struct LineupWidgetView: View {
    let data: WidgetData
    let date: Date
    let family: WidgetFamily

    var body: some View {
        let limit = family == .systemLarge ? 6 : 3
        let projects = data.projects
            .filter { $0.phase(on: date) != .finished }
            .sorted { ($0.next(on: date)?.due ?? .distantFuture) < ($1.next(on: date)?.due ?? .distantFuture) }
        if projects.isEmpty {
            EmptyWidgetView(family: family)
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 16 : 9) {
                if family == .systemLarge {
                    HStack {
                        Text("Prodline").display(22, 800).foregroundStyle(Theme.ink)
                        Spacer()
                        Label("\(data.streak)", systemImage: "flame.fill")
                            .font(.ui(13, .bold)).foregroundStyle(Theme.flame)
                    }
                }
                ForEach(projects.prefix(limit)) { p in
                    Link(destination: p.url) { row(p) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ p: WidgetProject) -> some View {
        let next = p.next(on: date)
        let large = family == .systemLarge
        let (day, of) = p.phaseDay(on: date)
        return HStack(spacing: 10) {
            WBadge(project: p, size: large ? 34 : 30)
            VStack(alignment: .leading, spacing: large ? 3 : 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.name).font(.ui(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    if large {
                        Spacer(minLength: 4)
                        Text("\(p.phase(on: date).title) · \(day)/\(of)").font(.ui(11, .semibold)).foregroundStyle(p.accent.text)
                    }
                }
                Text(next.map { "\($0.title) · \($0.dueText(from: date))" } ?? p.phase(on: date).title)
                    .font(.ui(12)).foregroundStyle(lateness(next) ? Theme.danger : Theme.secondary).lineLimit(1)
                if large {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.accent.base.opacity(0.15))
                            Capsule().fill(p.accent.base).frame(width: max(5, geo.size.width * p.phaseProgress(on: date)))
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 2)
                }
            }
            if !large {
                Spacer(minLength: 6)
                WRing(progress: p.phaseProgress(on: date), accent: p.accent, width: 4) { EmptyView() }
                    .frame(width: 24, height: 24)
            }
        }
    }

    private func lateness(_ c: WidgetCheckpoint?) -> Bool {
        c.map { Date.days(from: date, to: $0.due) < 0 } ?? false
    }
}

// MARK: - Empty

struct EmptyWidgetView: View {
    let family: WidgetFamily
    var text = "Create a project in Prodline to see it here."

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Text("Prodline")
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image("Mark").resizable().scaledToFit().frame(width: 28, height: 28)
                Spacer(minLength: 0)
                Text(text).font(.ui(13, .medium)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Cover lookup: in-app previews hand theirs in directly; the widget reads the App Group copy;
/// sample projects fall back to the app's bundled demo photos.
enum WidgetCovers {
    nonisolated(unsafe) static var overrides: [String: UIImage] = [:]

    static func image(_ id: String) -> UIImage? {
        if let img = overrides[id] { return img }
        if let img = SharedStore.cover(id) { return img }
        switch id {
        case "sample-habit": return UIImage(named: "Cover-habit-hero")
        case "sample-pixel": return UIImage(named: "Cover-pixel-quest")
        case "sample-shop": return UIImage(named: "Cover-side-shop")
        default: return nil
        }
    }
}
