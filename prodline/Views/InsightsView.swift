import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher
    @State private var metric: MetricKey = .visits
    @State private var range: TrendRange = .week
    @State private var scrub: Date?
    /// 0…1 left-to-right wipe; a new range or metric starts from an empty chart instead of morphing.
    @State private var reveal: CGFloat = 1

    enum TrendRange: String, CaseIterable, Identifiable {
        case day = "24H", week = "7D", month = "30D"
        var id: String { rawValue }
        var span: TimeInterval { switch self { case .day: 86_400; case .week: 7 * 86_400; case .month: 30 * 86_400 } }
        /// Bucket size: enough points for a smooth line without drawing every snapshot.
        var step: TimeInterval { switch self { case .day: 3_600; case .week: 6 * 3_600; case .month: 86_400 } }
        var label: String { switch self { case .day: "today"; case .week: "this week"; case .month: "this month" } }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date, project: String, value: Double
    }

    private struct Bar: Identifiable {
        let id = UUID()
        let project: String, isBuild: Bool, start: Date, end: Date, color: Color
    }

    private var bars: [Bar] {
        projects.flatMap { p in
            [Bar(project: p.name, isBuild: true, start: p.startDate, end: p.buildEnd, color: p.accent.base),
             Bar(project: p.name, isBuild: false, start: p.buildEnd, end: p.observeEnd, color: p.accent.base.opacity(0.35))]
        }
    }

    private func total(_ key: MetricKey) -> Double {
        projects.compactMap { refresher.value(key, for: $0) }.reduce(0, +)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Across \(projects.count) project\(projects.count == 1 ? "" : "s")", title: "Insights")

                if projects.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 36)).foregroundStyle(Theme.tertiary)
                        Text("Your timeline and traction appear here once you've created a project.")
                            .font(.ui(16)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .padding(.horizontal, 30)
                } else {
                    totals.padding(.horizontal, 16)
                    trend.padding(.horizontal, 16)
                    traction.padding(.horizontal, 16)
                    rhythm.padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }

    /// The three totals double as the switch for every chart below.
    private var totals: some View {
        HStack(spacing: 10) {
            ForEach(MetricKey.allCases) { k in
                let on = metric == k
                Button {
                    guard !on else { return }
                    Haptics.select()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { metric = k; scrub = nil }
                    replayChart()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: k.symbol).font(.system(size: 16, weight: .semibold))
                        Text(k.format(total(k))).display(22, 750)
                            .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                        Text(k.title).font(.ui(12, .medium)).opacity(on ? 0.75 : 1)
                            .foregroundStyle(on ? Color.white : Theme.secondary)
                    }
                    .foregroundStyle(on ? Color.white : Theme.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on ? Theme.ink : Theme.card))
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on ? Color.black : Theme.line).offset(y: 4))
                    .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Trend

    /// Each project's value at the end of every bucket, carried forward between snapshots.
    private var trendPoints: [Point] {
        let now = Date.now
        let start = now.addingTimeInterval(-range.span)
        let ticks = stride(from: start.timeIntervalSince1970, to: now.timeIntervalSince1970 - 1, by: range.step)
            .map { Date(timeIntervalSince1970: $0) } + [now]
        return projects.flatMap { p -> [Point] in
            let snaps = p.sortedSnapshots
            guard !snaps.isEmpty || refresher.value(metric, for: p) != nil else { return [] }
            var i = 0
            var last: Double?
            return ticks.map { t in
                while i < snaps.count, snaps[i].date <= t { last = snaps[i].value(metric); i += 1 }
                let v = t == now ? (refresher.value(metric, for: p) ?? last ?? 0) : (last ?? 0)
                return Point(date: t, project: p.name, value: v)
            }
        }
    }

    private var trend: some View {
        let points = trendPoints
        let names = projects.map(\.name)
        let byDate = Dictionary(grouping: points, by: \.date).mapValues { $0.reduce(0) { $0 + $1.value } }
        let dates = byDate.keys.sorted()
        let first = dates.first.flatMap { byDate[$0] } ?? 0
        let latest = dates.last.flatMap { byDate[$0] } ?? total(metric)
        let shownDate = scrub.flatMap { s in dates.min { abs($0.timeIntervalSince(s)) < abs($1.timeIntervalSince(s)) } }
        let shown = shownDate.flatMap { byDate[$0] } ?? latest
        let delta = latest - first

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title).eyebrow()
                    Text(metric.format(shown)).display(34, 800).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Group {
                        if let d = shownDate {
                            Text(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour()))
                        } else {
                            Text("\(delta >= 0 ? "+" : "−")\(metric.format(abs(delta))) \(range.label)")
                                .foregroundStyle(delta > 0 ? Theme.success : Theme.secondary)
                        }
                    }
                    .font(.ui(14, .semibold)).foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(TrendRange.allCases) { r in
                    Chip(title: r.rawValue, isOn: range == r) {
                        guard range != r else { return }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { range = r; scrub = nil }
                        replayChart()
                    }
                }
            }
            if points.isEmpty {
                Text("No numbers yet. Connect an endpoint to a project and its history shows up here.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                Chart {
                    ForEach(points) { pt in
                        AreaMark(x: .value("Time", pt.date), y: .value(metric.title, pt.value), stacking: .standard)
                            .foregroundStyle(by: .value("Project", pt.project))
                            .interpolationMethod(.monotone)
                            .opacity(0.85)
                    }
                    if let d = shownDate {
                        RuleMark(x: .value("Selected", d))
                            .foregroundStyle(Theme.ink.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: projects.map(\.accent.base))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .chartXSelection(value: $scrub)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(metric.format(d)) } }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                } }
                .frame(height: 220)
                // Never interpolate between two different data sets: swap instantly, then wipe in.
                .transaction { $0.animation = nil }
                .id("\(range.rawValue)-\(metric.rawValue)")
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * reveal)
                    }
                }
                .onChange(of: shownDate) { _, d in if d != nil { Haptics.select() } }
            }
        }
        .card()
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Rhythm", trailing: "build · observe")
            Chart {
                ForEach(bars) { b in
                    BarMark(xStart: .value("Start", b.start), xEnd: .value("End", b.end),
                            y: .value("Project", b.project), height: 20)
                        .foregroundStyle(b.color)
                        .clipShape(Capsule())
                }
                RuleMark(x: .value("Today", Date.now))
                    .foregroundStyle(Theme.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 4]))
                    .annotation(position: .top, alignment: .center) {
                        Text("Today").eyebrow(Theme.ink, size: 9)
                    }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .frame(height: CGFloat(max(projects.count, 1)) * 40 + 50)
        }
        .card()
    }

    private var traction: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("By project", trailing: metric.title)
            Chart(projects) { p in
                BarMark(x: .value("Project", p.name), y: .value(metric.title, refresher.value(metric, for: p) ?? 0))
                    .foregroundStyle(p.accent.base)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .annotation(position: .top) {
                        Text(metric.format(refresher.value(metric, for: p) ?? 0)).font(.ui(11, .semibold)).foregroundStyle(Theme.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 200)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: metric)
        }
        .card()
    }

    private func replayChart() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { reveal = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.easeOut(duration: 0.7)) { reveal = 1 }
        }
    }
}
