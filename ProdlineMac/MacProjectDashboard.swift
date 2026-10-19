import SwiftUI
import SwiftData
import Charts

/// One project as a desktop dashboard: the card and its connections on the left, traction across the
/// top, timeline, momentum and targets in a row, and the checkpoints as a board you work through.
struct MacProjectDashboard: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var allProjects: [Project]

    @State private var metric = ""
    @State private var showEdit = false
    @State private var showShare = false
    @State private var showConnection = false
    @State private var showCriteria = false
    @State private var showVerdict = false
    @State private var checkpointSheet: Milestone??
    @State private var editingIntegration: Integration?
    @State private var pickingIntegration = false
    @State private var reopening: Milestone?

    private var accent: Accent { project.accent }

    var body: some View {
        MacScroll {
            VStack(alignment: .leading, spacing: 28) {
                header
                HStack(alignment: .top, spacing: 28) {
                    rail.frame(width: 280)
                    VStack(alignment: .leading, spacing: 24) {
                        if ScheduleEngine.canShip(project) { shipBanner }
                        tractionCard
                        HStack(alignment: .top, spacing: 24) {
                            if project.phase() == .building || project.phase() == .upcoming {
                                MomentumCard(project: project, onConnect: { showConnection = true })
                                    .frame(maxWidth: .infinity)
                            }
                            SuccessCard(project: project, onSetTargets: { showCriteria = true }, onDecide: { showVerdict = true },
                                        onUndo: undoVerdict)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                checkpointBoard
            }
            .padding(.horizontal, 40).padding(.vertical, 28)
            .frame(maxWidth: 1360, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            AccentGlow(accent: accent).frame(height: 420).allowsHitTesting(false)
        }
        .background(Theme.background)
        .environment(\.accent, accent)
        .sheet(isPresented: $showEdit) { EditProjectSheet(project: project).frame(width: 480, height: 720) }
        .sheet(isPresented: $showShare) { ShareCardSheet(project: project).frame(width: 460, height: 780) }
        .sheet(isPresented: $showConnection) { ConnectionSheet(project: project).frame(width: 520, height: 720) }
        .sheet(isPresented: $showCriteria) { CriteriaSheet(project: project).frame(width: 480, height: 640) }
        .sheet(isPresented: $showVerdict) { VerdictSheet(project: project).frame(width: 480, height: 720) }
        .sheet(isPresented: Binding(get: { checkpointSheet != nil }, set: { if !$0 { checkpointSheet = nil } })) {
            if let m = checkpointSheet { CheckpointSheet(project: project, milestone: m).frame(width: 480, height: 640) }
        }
        .sheet(isPresented: $pickingIntegration) {
            IntegrationPicker(connected: Set(project.integrations.map(\.kind))) { kind in
                pickingIntegration = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    editingIntegration = Integration(kind: kind)
                }
            }
            .frame(width: 480, height: 680)
        }
        .sheet(item: $editingIntegration) { i in
            IntegrationEditor(project: project, integration: i, isNew: !project.integrations.contains { $0.id == i.id })
                .frame(width: 480, height: 720)
        }
        .confirmationDialog(reopening.map { "Reopen \($0.title)?" } ?? "", isPresented: Binding(get: { reopening != nil }, set: { if !$0 { reopening = nil } }),
                            titleVisibility: .visible) {
            Button("Mark as not done", role: .destructive) {
                if let m = reopening { MacActions.reopen(m, profile: profiles.first, projects: allProjects, context: context) }
                reopening = nil
            }
        } message: {
            Text((reopening?.xpEarned ?? 0) > 0 ? "You'll lose the \(reopening?.xpEarned ?? 0) XP it earned." : "It goes back to open.")
        }
        // Opening a project asks its services for fresh numbers.
        .task(id: project.id) { await refresher.refresh(projects: [project], context: context, force: true) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: project.phase().symbol)
                    Text(phaseLine)
                }
                .font(.ui(13, .semibold))
                .foregroundStyle(accent.on)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(accent.base))
                Text(project.name).display(46, 800).foregroundStyle(Theme.ink).lineLimit(1)
            }
            Spacer()
            Button { showShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .buttonStyle(.chunky(.neutral, height: 42, fullWidth: false))
            Button { showEdit = true } label: { Label("Edit", systemImage: "paintbrush") }
                .buttonStyle(.chunky(.neutral, height: 42, fullWidth: false))
            Menu {
                Button("Connection", systemImage: "bolt.horizontal") { showConnection = true }
                Button("Success targets", systemImage: "target") { showCriteria = true }
                if VerdictEngine.canDecide(project) {
                    Button("Keep, pivot or kill", systemImage: "scalemass") { showVerdict = true }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.card))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var phaseLine: String {
        switch project.phase() {
        case .upcoming: "Starts \(project.startDate.shortDay)"
        case .building: "Building · day \(project.dayInPhase) of \(project.buildDays)"
        case .observing: "Observing · day \(project.dayInPhase) of \(project.observeDays)"
        case .finished: project.verdict.map { $0.pastTense } ?? "Finished · decide"
        }
    }

    // MARK: Left rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProjectCardFace(project: project, refresher: refresher)
                .frame(width: 280, height: 392)
                .cardFloorShadow(width: 280)
                .padding(.bottom, 18)
            if !project.details.isEmpty {
                Text(project.details).font(.ui(15)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Connected").eyebrow(size: 11)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 10), count: 5), alignment: .leading, spacing: 10) {
                    ForEach(project.integrations) { i in
                        Button { editingIntegration = i } label: { IntegrationIcon(kind: i.kind, size: 40) }
                            .buttonStyle(MacLiftStyle())
                            .help(i.kind.title)
                    }
                    Button { pickingIntegration = true } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.secondary)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.inset))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    }
                    .buttonStyle(MacLiftStyle())
                    .help("Add integration")
                }
                if !project.githubRepo.isEmpty {
                    Label(project.githubRepo, systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.ui(13, .medium)).foregroundStyle(Theme.secondary)
                }
            }
            .card(padding: 18, radius: 22)
            timelineCard
        }
    }

    private var timelineCard: some View {
        let total = Double(project.buildDays + project.observeDays)
        let buildFrac = Double(project.buildDays) / total
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeline").font(.display(18, 750)).foregroundStyle(Theme.ink)
                Spacer()
                Text("Day \(max(Date.days(from: project.startDate, to: .now) + 1, 0)) of \(Int(total))").eyebrow(size: 10)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        Capsule().fill(accent.base).frame(width: max(w * buildFrac - 1.5, 0))
                        Capsule().fill(accent.base.opacity(0.3))
                    }
                    .frame(height: 12)
                    if project.phase() == .building || project.phase() == .observing {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.ink).frame(width: 4, height: 24)
                            .offset(x: max(0, min(w - 4, w * project.overallProgress - 2)))
                    }
                }
                .frame(height: 24)
            }
            .frame(height: 24)
            HStack {
                dateLabel("Start", project.startDate)
                Spacer()
                dateLabel("Launch", project.launchDay)
                Spacer()
                dateLabel("End", project.observeEnd.adding(days: -1))
            }
        }
        .card(padding: 18, radius: 22)
    }

    private func dateLabel(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).eyebrow(size: 9)
            Text(date.dayMonth).font(.ui(13, .semibold)).foregroundStyle(Theme.ink)
        }
    }

    // MARK: Traction

    private var tractionCard: some View {
        let shown = refresher.availableMetrics(for: project)
        let current = shown.contains(metric) ? metric : (shown.first ?? MetricKey.visits.rawValue)
        let series = project.sortedSnapshots.compactMap { s in s.valueIfPresent(current).map { (date: s.date, value: $0) } }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Traction").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                statusLabel
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(shown, id: \.self) { key in metricTile(key, selected: key == current) }
            }
            if series.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 30)).foregroundStyle(Theme.tertiary)
                    Text(project.hasDataSource ? "The chart fills in after a couple of syncs." : "Connect a service to see this project's numbers here.")
                        .font(.ui(14)).foregroundStyle(Theme.secondary)
                    if !project.hasDataSource {
                        Button("Add integration") { pickingIntegration = true }
                            .buttonStyle(.chunky(.accent, height: 40, fullWidth: false))
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
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
                    AxisMarks(position: .trailing) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(Stat.format(current, d)) } }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 240)
                .animation(.easeInOut, value: current)
            }
        }
        .card(padding: 22, radius: 26)
    }

    private func metricTile(_ key: String, selected: Bool) -> some View {
        Button {
            Haptics.select()
            withAnimation(.snappy) { metric = key }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: Stat.symbol(key)).font(.system(size: 14, weight: .semibold))
                Text(refresher.value(key, for: project).map { Stat.format(key, $0) } ?? "–")
                    .display(24, 750).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(Stat.title(key)).font(.ui(11, .semibold)).opacity(0.75).lineLimit(1)
            }
            .foregroundStyle(selected ? accent.on : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? accent.base : Theme.background))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch refresher.status[project.id] {
        case .live(let at):
            HStack(spacing: 5) {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                Text("Live · ") + Text(at, style: .relative)
            }
            .font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
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
                .frame(width: 48, height: 48).background(Circle().fill(accent.base))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to ship").display(22, 750).foregroundStyle(Theme.ink)
                Text(early > 0 ? "Every goal is done. Ship today and you're \(early) day\(early == 1 ? "" : "s") early."
                               : "Every goal is done, and it's launch day.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Let's ship") {
                guard let profile = profiles.first else { return }
                ScheduleEngine.shipNow(project, profile: profile, projects: allProjects, celebration: celebration, context: context)
            }
            .buttonStyle(.chunky(.accent, height: 48, fullWidth: false))
        }
        .card(padding: 20, radius: 24)
    }

    // MARK: Checkpoints

    private var checkpointBoard: some View {
        let ms = project.sortedMilestones
        let done = ms.filter(\.isDone).count
        let fromFile = project.followsPlanFile
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Checkpoints").display(26, 750).foregroundStyle(Theme.ink)
                Text("\(done) of \(ms.count) done").eyebrow(size: 11)
                Spacer()
                if fromFile {
                    Label("Follows prodline.json in \(project.githubRepo)", systemImage: "doc.text")
                        .font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
                } else {
                    Button { checkpointSheet = .some(nil) } label: { Label("Add checkpoint", systemImage: "plus") }
                        .buttonStyle(.chunky(.neutral, height: 38, fullWidth: false))
                }
            }
            ChunkyProgressBar(value: ms.isEmpty ? 0 : Double(done) / Double(ms.count), height: 10)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(ms) { m in checkpointColumn(m, fromFile: fromFile) }
            }
        }
    }

    private func checkpointColumn(_ m: Milestone, fromFile: Bool) -> some View {
        let isNext = m.id == project.nextMilestone?.id
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if m.isDone { reopening = m }
                    else { MacActions.complete(m, profile: profiles.first, projects: allProjects, celebration: celebration, context: context) }
                } label: { CheckpointRing(milestone: m, size: 32) }
                .buttonStyle(PressableStyle(scale: 0.85))
                .disabled(fromFile && m.hasGoals)
                .help(m.isDone ? "Done. Click to reopen" : "Mark \(m.title) done")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(m.title).font(.ui(16, .semibold)).foregroundStyle(m.isDone ? Theme.secondary : Theme.ink).lineLimit(1)
                        if m.isLaunch { Image(systemName: "flag.checkered").font(.system(size: 12)).foregroundStyle(accent.text) }
                    }
                    Text(m.macSubtitle).font(.ui(12)).foregroundStyle(m.isOverdue ? Theme.danger : Theme.secondary)
                }
                Spacer(minLength: 0)
                if !fromFile && !m.isDone {
                    Button { checkpointSheet = .some(m) } label: {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain).help("Edit checkpoint")
                }
            }
            if m.hasGoals {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(m.displayGoals) { g in
                        MacGoalRow(goal: g) {
                            MacActions.toggle(g, profile: profiles.first, projects: allProjects, celebration: celebration, context: context)
                        }
                    }
                }
            } else if !m.isDone {
                Text("No goals yet. The checkpoint finishes when you tick it.").font(.ui(13)).foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !fromFile && !m.isDone {
                Button { checkpointSheet = .some(m) } label: {
                    Label("Add goal", systemImage: "plus.circle").font(.ui(13, .semibold)).foregroundStyle(accent.text)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(isNext ? accent.base : .clear, lineWidth: 2.5))
        .opacity(m.isDone ? 0.75 : 1)
        .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
    }

    private func undoVerdict() {
        guard let profile = profiles.first else { return }
        Haptics.warning()
        withAnimation(.snappy) { VerdictEngine.reopen(project, profile: profile) }
        try? context.save()
    }
}
