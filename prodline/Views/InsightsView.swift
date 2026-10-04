import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher
    @State private var metric: MetricKey = .visits

    private struct Bar: Identifiable {
        let id = UUID()
        let project: String, phase: String, start: Date, end: Date
    }

    private var bars: [Bar] {
        projects.flatMap { p in
            [Bar(project: p.name, phase: "Build", start: p.startDate, end: p.buildEnd),
             Bar(project: p.name, phase: "Observe", start: p.buildEnd, end: p.observeEnd)]
        }
    }

    private func value(_ p: Project) -> Double {
        guard let c = refresher.current(for: p) else { return 0 }
        switch metric {
        case .visits: return c.visits
        case .socialViews: return c.social
        case .revenue: return c.revenue
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack { Text("Insights").font(.display(30)).foregroundStyle(Theme.ink); Spacer() }
                        .padding(.top, 8)

                    if projects.isEmpty {
                        Text("Add projects to see your timeline and traction.")
                            .font(.rounded(16, .bold)).foregroundStyle(Theme.inkLight)
                            .padding(.vertical, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Your rhythm")
                            Chart {
                                ForEach(bars) { b in
                                    BarMark(xStart: .value("Start", b.start), xEnd: .value("End", b.end),
                                            y: .value("Project", b.project), height: 18)
                                        .foregroundStyle(by: .value("Phase", b.phase))
                                        .cornerRadius(9)
                                }
                                RuleMark(x: .value("Today", Date.now))
                                    .foregroundStyle(Theme.red)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            }
                            .chartForegroundStyleScale(["Build": Theme.blue, "Observe": Theme.orange])
                            .frame(height: CGFloat(max(projects.count, 1)) * 44 + 40)
                        }
                        .padding(16).card()

                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Traction")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(MetricKey.allCases) { k in
                                        ChunkyChip(title: "\(k.icon) \(k.title)", isOn: metric == k) { metric = k }
                                    }
                                }
                            }
                            Chart(projects) { p in
                                BarMark(x: .value("Project", p.name), y: .value(metric.title, value(p)))
                                    .foregroundStyle(p.color)
                                    .cornerRadius(8)
                            }
                            .frame(height: 200)
                        }
                        .padding(16).card()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
