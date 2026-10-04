import SwiftUI
import SwiftData
import Charts

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var profiles: [Profile]

    @State private var metric: MetricKey = .visits
    @State private var apiKey = ""
    @State private var confirmDelete = false
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                metricTiles
                chartCard
                milestonesSection
                connectionSection
                Button("Delete project") { confirmDelete = true }
                    .buttonStyle(.chunky(.dangerOutline))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { apiKey = Keychain.get(project.id.uuidString) ?? "" }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for m in project.milestones ?? [] { Notifier.cancel(m) }
                Keychain.delete(project.id.uuidString)
                context.delete(project)
                try? context.save()
                dismiss()
            }
        } message: { Text("This also removes its milestones and metrics history.") }
    }

    private var header: some View {
        let phase = project.phase()
        return VStack(spacing: 12) {
            Text(project.emoji).font(.system(size: 54))
            PhaseBadge(phase: phase)
            ChunkyProgressBar(value: project.overallProgress, color: phase.color, height: 16)
            HStack {
                Text("Start \(project.startDate.shortDay)")
                Spacer()
                Text("Launch \(project.buildEnd.adding(days: -1).shortDay)")
                Spacer()
                Text("End \(project.observeEnd.adding(days: -1).shortDay)")
            }
            .font(.rounded(11, .bold)).foregroundStyle(Theme.inkLight)
        }
        .padding(16).card()
    }

    private var metricTiles: some View {
        let c = refresher.current(for: project)
        let values: [MetricKey: Double] = c.map { [.visits: $0.visits, .socialViews: $0.social, .revenue: $0.revenue] } ?? [:]
        return HStack(spacing: 10) {
            ForEach(MetricKey.allCases) { key in
                Button { Haptics.select(); withAnimation(.snappy) { metric = key } } label: {
                    VStack(spacing: 4) {
                        Text(key.icon).font(.system(size: 22))
                        Text(values[key].map(key.format) ?? "–")
                            .font(.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .contentTransition(.numericText())
                        Text(key.title).font(.rounded(11, .bold)).foregroundStyle(Theme.inkLight)
                            .minimumScaleFactor(0.7).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .card(tint: metric == key ? project.color : Theme.line,
                          fill: metric == key ? project.color.opacity(0.08) : .white)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .animation(.snappy, value: c?.visits)
    }

    private var chartCard: some View {
        let points = project.sortedSnapshots
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("\(metric.title) over time")
            if points.count < 2 {
                Text("Collecting data… the chart appears after a couple of syncs.")
                    .font(.rounded(14, .semibold)).foregroundStyle(Theme.inkLight)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(points, id: \.persistentModelID) { s in
                    AreaMark(x: .value("Time", s.date), y: .value(metric.title, s.value(metric)))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [project.color.opacity(0.35), project.color.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", s.date), y: .value(metric.title, s.value(metric)))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundStyle(project.color)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
            }
        }
        .padding(16).card()
    }

    private var milestonesSection: some View {
        VStack(spacing: 10) {
            SectionTitle("Milestones")
            ForEach(project.sortedMilestones) { m in
                MilestoneCard(milestone: m) {
                    if let profile = profiles.first {
                        ScheduleEngine.complete(m, profile: profile, celebration: celebration)
                        try? context.save()
                    }
                }
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Connection")
            TextField("https://yourapp.com/api/prodline", text: $project.endpoint)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .chunkyField()
            SecureField("API key", text: $apiKey)
                .chunkyField()
                .onChange(of: apiKey) { _, new in Keychain.set(new, for: project.id.uuidString) }
            if let err = refresher.errors[project.id] {
                Text(err).font(.rounded(13, .semibold)).foregroundStyle(Theme.red)
            } else if let testMessage {
                Text(testMessage).font(.rounded(13, .semibold)).foregroundStyle(Theme.greenDark)
            } else if project.endpoint.isEmpty {
                Text("Showing sample data until an endpoint is set.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.inkLight)
            }
            Button(testing ? "Testing…" : "Test connection") {
                testing = true
                testMessage = nil
                Task {
                    await refresher.refresh(projects: [project], context: context, force: true)
                    testing = false
                    if refresher.errors[project.id] == nil { testMessage = "Connected and synced ✓"; Haptics.success() }
                }
            }
            .buttonStyle(.chunky(.secondary))
            .disabled(testing)
        }
        .padding(16).card()
    }
}
