import SwiftUI
import SwiftData
import Charts

/// Opens on top of Dash without moving the card: the hero card is laid out at the tapped card's exact
/// screen frame and stays put, while everything around it fades in with a blur.
struct ProjectDetailView: View {
    @Bindable var project: Project
    /// Global frame of the tapped card. nil when opened from elsewhere (then the card fades in too).
    var cardFrame: CGRect? = nil
    var onClose: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var profiles: [Profile]

    @State private var metric: MetricKey = .visits
    @State private var showEdit = false
    @State private var showConnection = false
    @State private var confirmDelete = false
    @State private var drafting = false
    @State private var draftError: String?
    @State private var addingGoalTo: Milestone?
    @State private var newGoalTitle = ""
    /// Checkpoint being edited; `.some(nil)` adds a new one.
    @State private var checkpointSheet: Milestone?? = nil
    @Environment(GitHubService.self) private var github
    @State private var revealed = false
    @State private var scrolledAway = false
    /// How far the page is pulled down past the top; the glow stretches to fill it.
    @State private var overscroll: CGFloat = 0

    private var accent: Accent { project.accent }
    /// Same size and spot as on Dash, also when opened from elsewhere.
    private var heroFrame: CGRect? { cardFrame ?? DashLayout.lastCardFrame }
    private var heroWidth: CGFloat { heroFrame?.width ?? 240 }
    /// The card stays fully visible only while it sits exactly on top of its carousel twin.
    private var cardOpacity: Double { revealed || (cardFrame != nil && !scrolledAway) ? 1 : 0 }

    private func reveal(_ on: Bool, then: @escaping () -> Void = {}) {
        withAnimation(.easeOut(duration: on ? 0.38 : 0.26)) { revealed = on } completion: { then() }
    }

    private func close(then: @escaping () -> Void = {}) {
        reveal(false) {
            onClose()
            then()
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                hero
                VStack(spacing: 16) {
                    timelineCard
                    // Building: is it moving? Shipped: is anyone coming?
                    if project.phase() == .building || project.phase() == .upcoming {
                        MomentumCard(project: project, onConnect: { showConnection = true })
                    } else {
                        metricsCard
                    }
                    milestonesCard
                    connectionCard
                    Button("Delete project") { confirmDelete = true }
                        .buttonStyle(.chunky(.danger, height: 50))
                        .padding(.top, 8)
                }
                .opacity(revealed ? 1 : 0)
                .blur(radius: revealed ? 0 : 18)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 2 } action: { _, away in
            scrolledAway = away
        }
        .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, v in
            overscroll = v
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.background.opacity(revealed ? 1 : 0).ignoresSafeArea())
        .overlay(alignment: .top) {
            topBar.opacity(revealed ? 1 : 0).blur(radius: revealed ? 0 : 8)
        }
        .onAppear { reveal(true) }
        .environment(\.accent, accent)
        .refreshable { await refresher.refresh(projects: [project], context: context, force: true) }
        #if DEBUG
        .onAppear { if UserDefaults.standard.string(forKey: "PRODLINE_SHEET") == "connection" { showConnection = true } }
        #endif
        .sheet(isPresented: $showEdit) { EditProjectSheet(project: project) }
        .sheet(isPresented: $showConnection) { ConnectionSheet(project: project) }
        .sheet(isPresented: Binding(get: { checkpointSheet != nil }, set: { if !$0 { checkpointSheet = nil } })) {
            if let m = checkpointSheet { CheckpointSheet(project: project, milestone: m) }
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let p = project
                close {
                    for m in p.milestones ?? [] { Notifier.cancel(m) }
                    Keychain.delete(p.id.uuidString)
                    Keychain.delete("gh-" + p.id.uuidString)
                    context.delete(p)
                    try? context.save()
                }
            }
        } message: { Text("This also removes its deadlines and metrics history.") }
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            CircleIconButton(systemName: "xmark") { close() }
            Spacer()
            Menu {
                Button("Edit project & schedule", systemImage: "paintbrush") { showEdit = true }
                Button("Connection", systemImage: "bolt.horizontal") { showConnection = true }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(alignment: .top) {
            LinearGradient(colors: [Theme.background, Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .padding(.top, -80)
                .ignoresSafeArea()
                .opacity(0.9)
                .allowsHitTesting(false)
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ProjectCardFace(project: project, refresher: refresher)
                .frame(width: heroWidth)
                .opacity(cardOpacity)
                // The carousel already draws a shadow at this spot; ours takes over as the page fades in.
                .cardFloorShadow(width: heroWidth, strength: revealed ? 1 : 0)
                .padding(.top, heroFrame?.minY ?? 150)
                // Mirrors Dash: the phase pill sits where the page dots are.
                .padding(.bottom, DashLayout.shadowGap - 18)
            Group {
            HStack(spacing: 8) {
                Image(systemName: project.phase().symbol)
                Text(project.phase().title)
            }
            .font(.ui(14, .semibold))
            .foregroundStyle(accent.on)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(accent.base))
            if !project.details.isEmpty {
                Text(project.details)
                    .font(.ui(16))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .opacity(revealed ? 1 : 0)
            .blur(radius: revealed ? 0 : 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            AccentGlow(accent: accent)
                .frame(height: (heroFrame?.maxY ?? 480) + 60 + overscroll)
                .offset(y: -overscroll)
                .padding(.horizontal, -16)
                .opacity(revealed ? 1 : 0)
        }
    }

    // MARK: Timeline

    private var timelineCard: some View {
        let total = Double(project.buildDays + project.observeDays)
        let buildFrac = Double(project.buildDays) / total
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Timeline", trailing: "Day \(max(Date.days(from: project.startDate, to: .now) + 1, 0)) of \(Int(total))")
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Capsule().fill(accent.base).frame(width: w * buildFrac - 2)
                        Capsule().fill(accent.base.opacity(0.3))
                    }
                    .frame(height: 16)
                    // Today marker
                    if project.phase() != .finished && project.phase() != .upcoming {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2).fill(Theme.ink).frame(width: 4, height: 28)
                        }
                        .offset(x: max(0, min(w - 4, w * project.overallProgress - 2)))
                    }
                }
                .frame(height: 28)
            }
            .frame(height: 28)
            HStack {
                label("Start", project.startDate)
                Spacer()
                label("Launch", project.launchDay)
                Spacer()
                label("End", project.observeEnd.adding(days: -1))
            }
        }
        .card()
    }

    private func label(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).eyebrow(size: 10)
            Text(date.dayMonth).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
        }
    }

    // MARK: Metrics

    private var metricsCard: some View {
        let points = project.sortedSnapshots
        let extras = refresher.extras(for: project)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Traction").display(24, 700).foregroundStyle(Theme.ink)
                Spacer()
                statusLabel
            }
            HStack(spacing: 8) {
                ForEach(MetricKey.allCases) { key in
                    let selected = metric == key
                    Button {
                        Haptics.select()
                        withAnimation(.snappy) { metric = key }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: key.symbol).font(.system(size: 15, weight: .semibold))
                            Text(refresher.value(key, for: project).map(key.format) ?? "–")
                                .display(22, 700)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .contentTransition(.numericText())
                            Text(key.title).font(.ui(11, .semibold)).opacity(0.75).lineLimit(1)
                        }
                        .foregroundStyle(selected ? accent.on : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? accent.base : Theme.background))
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
            }
            .animation(.snappy, value: refresher.value(.visits, for: project))

            if points.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(Theme.tertiary)
                    Text("The chart fills in after a couple of syncs.").font(.ui(14)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(points, id: \.persistentModelID) { s in
                    AreaMark(x: .value("Time", s.date), y: .value(metric.title, s.value(metric)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [accent.base.opacity(0.32), accent.base.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", s.date), y: .value(metric.title, s.value(metric)))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .foregroundStyle(accent.base)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(metric == .revenue ? MetricKey.money(d) : MetricKey.count(d)) }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 190)
                .animation(.easeInOut, value: metric)
            }

            if !extras.isEmpty {
                VStack(spacing: 8) {
                    ForEach(extras, id: \.key) { e in
                        HStack {
                            Text(e.key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.ui(15)).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(MetricKey.count(e.value)).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .card()
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
        case .failing:
            HStack(spacing: 5) {
                Circle().fill(Theme.danger).frame(width: 7, height: 7)
                Text("Sync issue")
            }
            .font(.ui(12, .semibold)).foregroundStyle(Theme.danger)
        default:
            Text(project.hasEndpoint ? "Connecting" : "Sample data").eyebrow(size: 10)
        }
    }

    // MARK: Milestones

    private var milestonesCard: some View {
        let ms = project.sortedMilestones
        let done = ms.filter(\.isDone).count
        let canSuggest = GoalPlanner.isEnabled && ms.dropLast().contains { !$0.isDone && !$0.hasGoals }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Deadlines", trailing: "\(done)/\(ms.count) done")
            goalSources(ms)
            ChunkyProgressBar(value: ms.isEmpty ? 0 : Double(done) / Double(ms.count), height: 12)
                .padding(.bottom, 4)
            if canSuggest || drafting {
                Button { Task { await suggestGoals() } } label: {
                    HStack(spacing: 8) {
                        if drafting { ProgressView().tint(accent.text) } else { Image(systemName: "sparkles") }
                        Text(drafting ? "Planning goals on device" : "Suggest goals for open checkpoints")
                            .font(.ui(15, .semibold))
                        Spacer()
                    }
                    .foregroundStyle(accent.text)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.soft))
                }
                .buttonStyle(PressableStyle())
                .disabled(drafting)
            }
            if let draftError {
                Text(draftError).font(.ui(13)).foregroundStyle(Theme.danger)
            }
            ForEach(ms) { m in
                MilestoneLine(milestone: m,
                              onDone: { complete(m) },
                              onToggleGoal: { toggle($0) },
                              onDeleteGoal: { g in context.delete(g); try? context.save() },
                              onAddGoal: { newGoalTitle = ""; addingGoalTo = m },
                              onEdit: { checkpointSheet = .some(m) })
                if m.id != ms.last?.id { Divider().padding(.leading, 44) }
            }
            Button { checkpointSheet = .some(nil) } label: {
                Label("Add checkpoint", systemImage: "plus.circle")
                    .font(.ui(15, .semibold)).foregroundStyle(accent.text)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            Divider()
            GuideDisclosure(title: "How do goals work?") { GoalsGuideView() }
        }
        .card()
        .alert("New goal", isPresented: Binding(get: { addingGoalTo != nil }, set: { if !$0 { addingGoalTo = nil } })) {
            TextField("e.g. Ship pricing page", text: $newGoalTitle)
            Button("Add") {
                if let m = addingGoalTo {
                    GoalEngine.addGoals([newGoalTitle], source: .manual, to: m, context: context)
                    try? context.save()
                    Haptics.success()
                }
                addingGoalTo = nil
            }
            Button("Cancel", role: .cancel) { addingGoalTo = nil }
        } message: {
            Text("The checkpoint completes once all of its goals are done.")
        }
    }

    /// Where this project's goals come from, said once instead of under every goal.
    @ViewBuilder
    private func goalSources(_ ms: [Milestone]) -> some View {
        let present = Set(ms.flatMap { $0.goals ?? [] }.map(\.source))
        let order: [GoalSource] = [.repoFile, .github, .api, .metric, .ai, .manual]
        let sources = order.filter(present.contains)
        if !sources.isEmpty {
            HStack(spacing: 12) {
                Text("Goals from").font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
                ForEach(sources, id: \.self) { src in
                    Label(src.shortName, systemImage: src.symbol)
                        .font(.ui(12, .semibold)).foregroundStyle(Theme.inkSoft)
                        .labelStyle(.titleAndIcon)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func complete(_ m: Milestone) {
        guard let profile = profiles.first else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            ScheduleEngine.complete(m, profile: profile, celebration: celebration)
        }
        try? context.save()
    }

    private func toggle(_ g: Goal) {
        guard !g.source.isAutomatic else { return }
        Haptics.select()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { g.setDone(!g.isDone) }
        if g.isDone, let profile = profiles.first {
            GoalEngine.awardGoalXP(projects: [project], profile: profile, celebration: celebration)
            GoalEngine.autoComplete(projects: [project], profile: profile, celebration: celebration)
        }
        try? context.save()
    }

    private func suggestGoals() async {
        drafting = true
        draftError = nil
        defer { drafting = false }
        let ms = project.sortedMilestones
        do {
            let plan = try await GoalPlanner.draft(
                name: project.name, details: project.details, buildDays: project.buildDays,
                deadlines: ms.map { .init(title: $0.title, date: $0.dueDate) },
                github: github.snapshots[project.id])
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                for (i, titles) in plan where (1...ms.count).contains(i) {
                    let m = ms[i - 1]
                    guard !m.isDone, !m.hasGoals else { continue }
                    GoalEngine.addGoals(titles, source: .ai, to: m, context: context)
                }
            }
            try? context.save()
            Haptics.success()
        } catch {
            draftError = "Couldn't plan goals right now. Try again in a moment."
        }
    }

    // MARK: Connection

    private var connectionCard: some View {
        Button { showConnection = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent.on)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.base))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data connection").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Text(connectionSubtitle).font(.ui(14)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
            .card()
        }
        .buttonStyle(PressableStyle())
    }

    private var connectionSubtitle: String {
        switch refresher.status[project.id] {
        case .failing(let msg, let retry): "\(msg) Retrying \(retry.formatted(.relative(presentation: .named)))."
        case .live: project.endpoint
        default: project.hasEndpoint ? project.endpoint : "Not connected · showing sample data"
        }
    }
}

/// A deadline with its goals. Without goals it's ticked by hand; with goals it completes itself.
struct MilestoneLine: View {
    let milestone: Milestone
    var onDone: () -> Void
    var onToggleGoal: (Goal) -> Void = { _ in }
    var onDeleteGoal: (Goal) -> Void = { _ in }
    var onAddGoal: () -> Void = {}
    var onEdit: (() -> Void)? = nil
    @Environment(\.accent) private var accent
    @Environment(DataRefresher.self) private var refresher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    guard !milestone.isDone else { return }
                    onDone()
                } label: {
                    ZStack {
                        if milestone.hasGoals && !milestone.isDone {
                            // Progress ring: the checkpoint closes when the ring does.
                            Circle().stroke(Theme.line, lineWidth: 3)
                            Circle().trim(from: 0, to: progress)
                                .stroke(accent.base, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        } else {
                            Circle().strokeBorder(milestone.isDone ? accent.base : Theme.tertiary, lineWidth: 2.5)
                        }
                        if milestone.isDone {
                            Circle().fill(accent.base)
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(accent.on)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .disabled(milestone.isDone)
                .accessibilityLabel(milestone.isDone ? "Done" : "Mark \(milestone.title) done")

                Button { onEdit?() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(milestone.title).font(.ui(16, .semibold))
                                    .foregroundStyle(milestone.isDone ? Theme.secondary : Theme.ink)
                                if milestone.isLaunch { Image(systemName: "flag.checkered").font(.system(size: 12)).foregroundStyle(accent.text) }
                            }
                            Text(subtitle).font(.ui(13)).foregroundStyle(milestone.isOverdue ? Theme.danger : Theme.secondary)
                        }
                        Spacer()
                        if onEdit != nil, !milestone.isDone {
                            Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onEdit == nil || milestone.isDone)
            }

            if milestone.hasGoals || !milestone.isDone {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(milestone.sortedGoals) { g in goalRow(g) }
                    if !milestone.isDone {
                        Button(action: onAddGoal) {
                            Label("Add goal", systemImage: "plus")
                                .font(.ui(13, .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 6)
    }

    /// Metric goals show live progress ("412 of 500"), others their source.
    /// Live progress for number goals ("412 of 500"); where goals come from is said once in the card heading.
    private func goalCaption(_ g: Goal) -> String? {
        guard let key = g.metricKey, let target = g.target, !g.isDone, let project = milestone.project,
              let v = GoalEngine.value(for: key, project: project, refresher: refresher) else { return nil }
        let isMoney = key == MetricKey.revenue.rawValue
        let fmt: (Double) -> String = { isMoney ? MetricKey.money($0) : MetricKey.count($0) }
        return "\(fmt(v)) of \(fmt(target))"
    }

    private var progress: Double {
        let gs = milestone.goals ?? []
        return gs.isEmpty ? 0 : Double(gs.filter(\.isDone).count) / Double(gs.count)
    }

    @ViewBuilder
    private func goalRow(_ g: Goal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onToggleGoal(g) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(g.isDone ? accent.base : Theme.tertiary, lineWidth: 2)
                    if g.isDone {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent.base)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(accent.on)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .disabled(g.source.isAutomatic)
            .accessibilityLabel(g.source.isAutomatic ? "\(g.title), completes automatically" : "Toggle \(g.title)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(g.title)
                        .font(.ui(14, .medium))
                        .foregroundStyle(g.isDone ? Theme.secondary : Theme.ink)
                        .strikethrough(g.isDone, color: Theme.secondary)
                    if let link = URL(string: g.url), !g.url.isEmpty {
                        Link(destination: link) {
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary)
                        }
                        .accessibilityLabel("Open \(g.title)")
                    }
                }
                if let caption = goalCaption(g) {
                    Text(caption).font(.ui(11, .medium)).foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if !g.source.isAutomatic {
                Button("Delete goal", systemImage: "trash", role: .destructive) { onDeleteGoal(g) }
            }
        }
    }

    private var subtitle: String {
        if let done = milestone.completedAt {
            return milestone.completedOnTime ? "Done \(done.dayMonth) · on time" : "Done \(done.dayMonth) · late"
        }
        var s: String
        if milestone.isOverdue { s = "Overdue since \(milestone.dueDate.shortDay)" }
        else if milestone.isDueToday { s = "Due today" }
        else { s = milestone.dueDate.shortDay }
        if milestone.hasGoals {
            let gs = milestone.goals ?? []
            s += " · \(gs.filter(\.isDone).count)/\(gs.count) goals"
        }
        return s
    }
}

// MARK: - Sheets

struct EditProjectSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var details = ""
    @State private var imageData: Data?
    @State private var photoHex: Int?
    @State private var locked = false
    @State private var accentHex = 0
    @State private var startDate = Date.now
    @State private var buildDays = 14
    @State private var observeDays = 28
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    private var scheduleChanged: Bool {
        startDate.startOfDay != project.startDate || buildDays != project.buildDays || observeDays != project.observeDays
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit project").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CardCoverEditor(name: name, imageData: $imageData, accentHex: $accentHex,
                                    photoHex: $photoHex, lockedToPhoto: $locked)
                        .frame(width: 220)
                        .frame(maxWidth: .infinity)
                    AccentSlider(accentHex: $accentHex, locked: $locked, photoHex: photoHex)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").eyebrow()
                        TextField("Name", text: $name).inputField()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").eyebrow()
                        TextField("", text: $details, prompt: Text("What is it, who is it for?").foregroundStyle(Theme.tertiary),
                                  axis: .vertical)
                            .lineLimit(2...6)
                            .padding(.vertical, 14)
                            .inputField()
                    }
                    scheduleSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar {
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { project.name = trimmed }
                project.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
                project.coverImage = imageData
                project.accentHex = accentHex
                if scheduleChanged {
                    ScheduleEngine.changeSchedule(project, start: startDate, buildDays: buildDays, observeDays: observeDays,
                                                  profile: profiles.first, context: context)
                }
                try? context.save()
                Haptics.success()
                dismiss()
            }
            .buttonStyle(.chunky)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, Accent(hex: accentHex))
        .onAppear {
            name = project.name
            details = project.details
            imageData = project.coverImage
            accentHex = project.accentHex
            photoHex = project.cover.flatMap(ImageTools.dominantAccentHex)
            locked = photoHex == project.accentHex
            startDate = project.startDate
            buildDays = project.buildDays
            observeDays = project.observeDays
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Schedule").eyebrow()
            HStack {
                Text("Start").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(project.accent.text)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Build phase").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(buildDays.durationText).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                }
                ChunkySlider(value: $buildDays, range: 3...42)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Observe phase").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(observeDays.durationText).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                }
                ChunkySlider(value: $observeDays, range: 7...90)
            }
            Text(scheduleChanged
                 ? "Launch moves to \(startDate.startOfDay.adding(days: buildDays - 1).shortDay). Open checkpoints move along; finished ones and their goals stay."
                 : "Launch on \(project.launchDay.shortDay), traction review until \(project.observeEnd.adding(days: -1).shortDay).")
                .font(.ui(13)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16, radius: 22)
    }
}

struct ConnectionSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(GitHubService.self) private var github
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var probe: ProbeState = .idle
    @State private var repo = ""
    @State private var token = ""
    @State private var repoCheck: RepoCheck = .idle

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connection").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ConnectionFields(endpoint: $endpoint, apiKey: $apiKey, probe: $probe)
                    Divider()
                    GitHubFields(repo: $repo, token: $token, check: $repoCheck)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar {
            Button("Save") {
                project.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
                Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: project.id.uuidString)
                project.githubRepo = GitHubRepoRef(repo)?.slug ?? ""
                Keychain.set(token.trimmingCharacters(in: .whitespaces), for: "gh-" + project.id.uuidString)
                if case .ok(let snap) = repoCheck { GoalEngine.syncGitHub(snap, project: project, context: context) }
                try? context.save()
                Haptics.success()
                Task {
                    await refresher.refresh(projects: [project], context: context, force: true)
                    if let snap = (await github.refresh(projects: [project], force: true)).isEmpty ? nil : github.snapshots[project.id] {
                        GoalEngine.syncGitHub(snap, project: project, context: context)
                        try? context.save()
                    }
                }
                dismiss()
            }
            .buttonStyle(.chunky)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .onAppear {
            endpoint = project.endpoint
            apiKey = Keychain.get(project.id.uuidString) ?? ""
            repo = project.githubRepo
            token = Keychain.get("gh-" + project.id.uuidString) ?? ""
        }
    }
}

/// Rename, move or delete a checkpoint, or add a new one.
struct CheckpointSheet: View {
    let project: Project
    /// nil adds a new checkpoint.
    let milestone: Milestone?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @State private var name = ""
    @State private var due = Date.now.startOfDay
    @State private var confirmDelete = false

    private var range: ClosedRange<Date> {
        let lo = min(project.startDate, .now.startOfDay)
        return lo...max(project.observeEnd, due, lo)
    }
    private var autoName: String {
        guard let m = milestone else { return "Checkpoint" }
        return m.titleIsCustom ? "Checkpoint" : m.title
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(milestone == nil ? "New checkpoint" : "Edit checkpoint").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").eyebrow()
                        TextField("", text: $name, prompt: Text(autoName).foregroundStyle(Theme.tertiary))
                            .inputField()
                        Text("Leave empty for the automatic name. A name you set here wins over one from prodline.json.")
                            .font(.ui(13)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Due").eyebrow()
                        DatePicker("Due", selection: $due, in: range, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(project.accent.text)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                    }
                    if let m = milestone, !m.isLaunch {
                        Button("Delete checkpoint") { confirmDelete = true }
                            .buttonStyle(.chunky(.danger, height: 50))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar {
                Button(milestone == nil ? "Add checkpoint" : "Save", action: save).buttonStyle(.chunky)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .onAppear {
            if let m = milestone {
                name = m.titleIsCustom || !ScheduleEngine.isAutoName(m.title) ? m.title : ""
                due = m.dueDate
            } else {
                // Default: halfway between today and the next open deadline.
                let next = project.nextMilestone?.dueDate ?? project.launchDay
                due = max(Date.now.startOfDay, project.startDate).adding(days: max(1, Date.days(from: .now, to: next) / 2))
            }
        }
        .confirmationDialog("Delete this checkpoint?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let m = milestone { ScheduleEngine.delete(m, context: context) }
                try? context.save()
                dismiss()
            }
        } message: { Text("Its goals are removed too.") }
    }

    private func save() {
        if let m = milestone {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep a repo-given name unless the user typed something different.
            if trimmed != m.title || m.titleIsCustom { ScheduleEngine.rename(m, to: trimmed) }
            if m.dueDate != due.startOfDay { ScheduleEngine.reschedule(m, to: due, profile: profiles.first) }
        } else {
            ScheduleEngine.addCheckpoint(to: project, title: name, due: due, profile: profiles.first, context: context)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
