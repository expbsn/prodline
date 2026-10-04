import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher
    @State private var metric: MetricKey = .visits

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
                    rhythm.padding(.horizontal, 16)
                    traction.padding(.horizontal, 16)
                    growth.padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var totals: some View {
        HStack(spacing: 10) {
            ForEach(MetricKey.allCases) { k in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: k.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(k.format(total(k))).font(.display(22, 750)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                    Text(k.title).font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
                }
                .card(padding: 14, radius: 22)
            }
        }
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
            SectionTitle("Traction")
            HStack(spacing: 8) {
                ForEach(MetricKey.allCases) { k in
                    Chip(title: k.title, isOn: metric == k) { metric = k }
                }
            }
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

    private var growth: some View {
        let cutoff = Date.now.adding(days: -14)
        let series = projects.map { p in (p, p.sortedSnapshots.filter { $0.date >= cutoff }) }.filter { $0.1.count > 1 }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Last 14 days", trailing: metric.title)
            if series.isEmpty {
                Text("Not enough history yet.").font(.ui(14)).foregroundStyle(Theme.secondary)
            } else {
                Chart {
                    ForEach(series, id: \.0.id) { p, points in
                        ForEach(points, id: \.persistentModelID) { s in
                            LineMark(x: .value("Time", s.date), y: .value(metric.title, s.value(metric)),
                                     series: .value("Project", p.name))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .foregroundStyle(p.accent.base)
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 180)
            }
        }
        .card()
    }
}
