import SwiftUI
import SwiftData
import Charts

/// One project as a desktop page. Wide: the card next to traction, the project's connections and timeline
/// next to its targets, then the checkpoints full width with their goals, like on the iPhone. Narrow
/// windows get the same parts in one column.
struct MacProjectDashboard: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var allProjects: [Project]

    @State private var width: CGFloat = 1000
    @State private var metric = ""
    @State private var showEdit = false
    @State private var showShare = false
    @State private var showConnection = false
    @State private var showCriteria = false
    @State private var showVerdict = false
    @State private var checkpointSheet: Milestone??
    @State private var editingIntegration: Integration?
    @State private var pickingIntegration = false

    private var accent: Accent { project.accent }
    /// Two columns once there's room for the card next to a usable chart.
    private var wide: Bool { width >= 780 }
    private let cardWidth: CGFloat = 250
    private var cardHeight: CGFloat { cardWidth * 7 / 5 }

    var body: some View {
        MacScroll {
            VStack(alignment: .leading, spacing: 26) {
                header
                if ScheduleEngine.canShip(project) { shipBanner }
                if wide { wideTop } else { narrowTop }
                MacCheckpointList(project: project, onEdit: { checkpointSheet = .some($0) }, onAdd: { checkpointSheet = .some(nil) })
            }
            .padding(.horizontal, wide ? 40 : 24).padding(.top, 30).padding(.bottom, 40)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
            // The project's color washes the top of the page only, and scrolls away with it (as on the iPhone).
            .background(alignment: .top) {
                AccentGlow(accent: accent)
                    .frame(height: 440)
                    .padding(.top, -60)
                    // Reaches under the sidebar's glass too, so the color spans the whole window top.
                    .backgroundExtensionEffect()
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Theme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .environment(\.accent, accent)
        .sheet(isPresented: $showEdit) { EditProjectSheet(project: project).macSheet(width: 820, height: 620) }
        .sheet(isPresented: $showShare) { ShareCardSheet(project: project).macSheet(width: 760, height: 640) }
        .sheet(isPresented: $showConnection) { ConnectionSheet(project: project).macSheet(width: 860, height: 640) }
        .sheet(isPresented: $showCriteria) { CriteriaSheet(project: project).macSheet(width: 480, height: 640) }
        .sheet(isPresented: $showVerdict) { VerdictSheet(project: project).macSheet(width: 900, height: 640) }
        .sheet(isPresented: Binding(get: { checkpointSheet != nil }, set: { if !$0 { checkpointSheet = nil } })) {
            if let m = checkpointSheet { CheckpointSheet(project: project, milestone: m).macSheet(width: 820, height: 600) }
        }
        .sheet(isPresented: $pickingIntegration) {
            IntegrationPicker(connected: Set(project.integrations.map(\.kind))) { kind in
                pickingIntegration = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    editingIntegration = Integration(kind: kind)
                }
            }
            .macSheet(width: 860, height: 640)
        }
        .sheet(item: $editingIntegration) { i in
            IntegrationEditor(project: project, integration: i, isNew: !project.integrations.contains { $0.id == i.id })
                .macSheet(width: 860, height: 600)
        }
        // Opening a project asks its services for fresh numbers.
        .task(id: project.id) { await refresher.refresh(projects: [project], context: context, force: true) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: project.phase().symbol)
                    Text(phaseLine).lineLimit(1)
                }
                .font(.ui(13, .semibold))
                .foregroundStyle(accent.on)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(accent.base))
                Text(project.name).display(44, 800).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            // Labels while they fit, icons when the window gets narrow.
            ViewThatFits(in: .horizontal) {
                actions(labels: true)
                actions(labels: false)
            }
        }
    }

    private func actions(labels: Bool) -> some View {
        HStack(spacing: 10) {
            if labels {
                Button { showShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.chunky(.neutral, height: 40, fullWidth: false))
                Button { showEdit = true } label: { Label("Edit", systemImage: "paintbrush") }
                    .buttonStyle(.chunky(.neutral, height: 40, fullWidth: false))
            } else {
                MacRoundButton(symbol: "square.and.arrow.up", help: "Share") { showShare = true }
                MacRoundButton(symbol: "paintbrush", help: "Edit") { showEdit = true }
            }
            Menu {
                Button("Connection", systemImage: "bolt.horizontal") { showConnection = true }
                Button("Success targets", systemImage: "target") { showCriteria = true }
                if VerdictEngine.canDecide(project) {
                    Button("Keep, pivot or kill", systemImage: "scalemass") { showVerdict = true }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .fixedSize()
    }

    private var phaseLine: String {
        switch project.phase() {
        case .upcoming: "Starts \(project.startDate.shortDay)"
        case .building: "Building · day \(project.dayInPhase) of \(project.buildDays)"
        case .observing: "Observing · day \(project.dayInPhase) of \(project.observeDays)"
        case .finished: project.verdict.map { $0.pastTense } ?? "Finished · decide"
        }
    }

    // MARK: Layouts

    /// Row 1: card | traction (same height). Row 2: connections and timeline | targets and momentum.
    private var wideTop: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 26, verticalSpacing: 26) {
            GridRow {
                projectCard
                tractionCard.frame(height: cardHeight)
            }
            GridRow {
                VStack(spacing: 18) {
                    connectedCard
                    timelineCard
                }
                .frame(width: cardWidth)
                VStack(spacing: 18) {
                    SuccessCard(project: project, onSetTargets: { showCriteria = true }, onDecide: { showVerdict = true },
                                onUndo: undoVerdict)
                    if project.phase() == .building || project.phase() == .upcoming {
                        MomentumCard(project: project, onConnect: { showConnection = true })
                    }
                }
            }
        }
    }

    private var narrowTop: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ProjectCardFace(project: project, refresher: refresher)
                    .frame(width: 170, height: 238)
                VStack(alignment: .leading, spacing: 18) {
                    connectedCard
                    if !project.details.isEmpty {
                        Text(project.details).font(.ui(14)).foregroundStyle(Theme.inkSoft).lineLimit(3)
                    }
                }
            }
            tractionCard.frame(height: 330)
            timelineCard
            SuccessCard(project: project, onSetTargets: { showCriteria = true }, onDecide: { showVerdict = true }, onUndo: undoVerdict)
            if project.phase() == .building || project.phase() == .upcoming {
                MomentumCard(project: project, onConnect: { showConnection = true })
            }
        }
    }

    private var projectCard: some View {
        ProjectCardFace(project: project, refresher: refresher)
            .frame(width: cardWidth, height: cardHeight)
            .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
    }

    // MARK: Cards

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected").eyebrow(size: 11)
                Spacer()
                if !project.githubRepo.isEmpty {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondary).help("GitHub: \(project.githubRepo)")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(project.integrations) { i in
                    Button { editingIntegration = i } label: { IntegrationIcon(kind: i.kind, size: 36) }
                        .buttonStyle(MacLiftStyle())
                        .help(i.kind.title)
                }
                Button { pickingIntegration = true } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.secondary)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.inset))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .buttonStyle(MacLiftStyle())
                .help("Add integration")
            }
        }
        .card(padding: 16, radius: 22)
    }

    private var timelineCard: some View {
        let total = Double(project.buildDays + project.observeDays)
        let buildFrac = Double(project.buildDays) / total
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").cardTitle(17).foregroundStyle(Theme.ink)
                Spacer(minLength: 6)
                Text("Day \(min(max(Date.days(from: project.startDate, to: .now) + 1, 0), Int(total))) of \(Int(total))")
                    .eyebrow(size: 10).lineLimit(1)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        Capsule().fill(accent.base).frame(width: max(w * buildFrac - 1.5, 0))
                        Capsule().fill(accent.base.opacity(0.3))
                    }
                    .frame(height: 10)
                    if project.phase() == .building || project.phase() == .observing {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.ink).frame(width: 4, height: 22)
                            .offset(x: max(0, min(w - 4, w * project.overallProgress - 2)))
                    }
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            HStack {
                dateLabel("Start", project.startDate)
                Spacer(minLength: 4)
                dateLabel("Launch", project.launchDay)
                Spacer(minLength: 4)
                dateLabel("End", project.observeEnd.adding(days: -1))
            }
        }
        .card(padding: 16, radius: 22)
    }

    private func dateLabel(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).eyebrow(size: 9)
            Text(date.dayMonth).font(.ui(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        }
    }

    // MARK: Traction

    /// Three numbers, ones that actually have a value first (the picked ones when there are more).
    private var tractionKeys: (shown: [String], available: [String]) {
        let available = refresher.availableMetrics(for: project)
        let withValue = available.filter { (refresher.value($0, for: project) ?? 0) > 0 }
        let pool = withValue.count >= 3 ? withValue : withValue + available.filter { !withValue.contains($0) }
        var out: [String] = []
        for k in project.pickedMetrics + pool where out.count < 3 && pool.contains(k) && !out.contains(k) { out.append(k) }
        return (out, available)
    }

    private var tractionCard: some View {
        let (shown, available) = tractionKeys
        let current = shown.contains(metric) ? metric : (shown.first ?? MetricKey.visits.rawValue)
        let series = ChartSeries.make(project, key: current)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Traction").cardTitle(24).foregroundStyle(Theme.ink)
                Spacer()
                statusLabel
            }
            HStack(spacing: 10) {
                ForEach(shown, id: \.self) { key in metricTile(key, selected: key == current, shown: shown, available: available) }
            }
            if series.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(Theme.tertiary)
                    Text(project.hasDataSource ? "The chart fills in after a couple of syncs." : "Connect a service and the chart fills in from here.")
                        .font(.ui(14)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    if !project.hasDataSource {
                        Button("Add integration") { pickingIntegration = true }
                            .buttonStyle(.chunky(.accent, height: 38, fullWidth: false))
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    Chart(Array(series.enumerated()), id: \.offset) { _, s in
                        AreaMark(x: .value("Time", s.date), y: .value(Stat.title(current), s.value))
                            .interpolationMethod(.linear)
                            .foregroundStyle(LinearGradient(colors: [accent.base.opacity(0.32), accent.base.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Time", s.date), y: .value(Stat.title(current), s.value))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(accent.base)
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                            AxisGridLine().foregroundStyle(Theme.line)
                            AxisValueLabel { if let d = v.as(Double.self) { Text(axisLabel(current, d)) } }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: wide ? 6 : 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                        }
                    }
                    // A new metric fades in rather than the line morphing point by point into the other one.
                    .id(current)
                    .transition(.opacity)
                }
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.card))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
    }

    /// Axis labels without cents: $400, 1.2K.
    private func axisLabel(_ key: String, _ v: Double) -> String {
        guard key == Stat.revenue else { return Stat.format(key, v) }
        return v >= 10_000 ? MetricKey.money(v) : "$" + Int(v.rounded()).formatted()
    }

    /// Click to chart it; right-click to swap it for another number the project gets.
    private func metricTile(_ key: String, selected: Bool, shown: [String], available: [String]) -> some View {
        Button {
            Haptics.select()
            withAnimation(.snappy) { metric = key }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Stat.symbol(key)).font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(refresher.value(key, for: project).map { Stat.format(key, $0) } ?? "–")
                        .display(22, 750).lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(Stat.title(key)).font(.ui(11, .semibold)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? accent.on : Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? accent.base : Theme.background))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .contextMenu {
            MetricSwapMenu(key: key, shown: shown, available: available, value: { refresher.value($0, for: project) }) { new in
                project.pickedMetrics = Stat.swap(key, for: new, shown: shown)
                try? context.save()
                withAnimation(.snappy) { metric = new }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch refresher.status[project.id] {
        case .live(let at):
            HStack(spacing: 5) {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                Text("Live · ") + Text(at, style: .relative)
            }
            .font(.ui(12, .semibold)).foregroundStyle(Theme.secondary).lineLimit(1)
        case .failing(let why, _):
            HStack(spacing: 5) {
                Circle().fill(Theme.danger).frame(width: 7, height: 7)
                Text("Sync issue")
            }
            .font(.ui(12, .semibold)).foregroundStyle(Theme.danger)
            .help(why)
        default:
            Text(project.hasDataSource ? "Connecting" : "Sample data").eyebrow(size: 10)
        }
    }

    private var shipBanner: some View {
        let early = Date.days(from: .now, to: project.launchDay)
        return HStack(spacing: 16) {
            Image(systemName: "paperplane.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(accent.on)
                .frame(width: 46, height: 46).background(Circle().fill(accent.base))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to ship").cardTitle(21).foregroundStyle(Theme.ink)
                Text(early > 0 ? "Every goal is done. Ship today and you're \(early) day\(early == 1 ? "" : "s") early."
                               : "Every goal is done, and it's launch day.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 12)
            Button("Let's ship") {
                guard let profile = profiles.first else { return }
                ScheduleEngine.shipNow(project, profile: profile, projects: allProjects, celebration: celebration, context: context)
            }
            .buttonStyle(.chunky(.accent, height: 46, fullWidth: false))
        }
        .card(padding: 18, radius: 24)
    }

    private func undoVerdict() {
        guard let profile = profiles.first else { return }
        Haptics.warning()
        withAnimation(.snappy) { VerdictEngine.reopen(project, profile: profile) }
        try? context.save()
    }
}

/// Round icon button in the page header (narrow windows).
struct MacRoundButton: View {
    let symbol: String
    let help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.card))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help(help)
    }
}
