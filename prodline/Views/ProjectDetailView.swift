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
    @State private var showEdit = false
    @State private var showConnection = false
    @State private var confirmDelete = false

    private var accent: Accent { project.accent }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                hero
                timelineCard
                metricsCard
                milestonesCard
                connectionCard
                Button("Delete project") { confirmDelete = true }
                    .buttonStyle(.chunky(.danger, height: 50))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .environment(\.accent, accent)
        .refreshable { await refresher.refresh(projects: [project], context: context, force: true) }
        #if DEBUG
        .onAppear { if UserDefaults.standard.string(forKey: "PRODLINE_SHEET") == "connection" { showConnection = true } }
        #endif
        .sheet(isPresented: $showEdit) { EditProjectSheet(project: project) }
        .sheet(isPresented: $showConnection) { ConnectionSheet(project: project) }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for m in project.milestones ?? [] { Notifier.cancel(m) }
                Keychain.delete(project.id.uuidString)
                dismiss()
                context.delete(project)
                try? context.save()
            }
        } message: { Text("This also removes its deadlines and metrics history.") }
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            CircleIconButton(systemName: "xmark") { dismiss() }
            Spacer()
            Menu {
                Button("Edit name & cover", systemImage: "paintbrush") { showEdit = true }
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
                .frame(width: 210)
                .shadow(color: accent.base.opacity(0.35), radius: 26, y: 14)
                .padding(.top, 118)
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
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            LinearGradient(colors: [accent.base.opacity(0.28), accent.base.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 480)
                .padding(.horizontal, -16)
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
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Deadlines", trailing: "\(done)/\(ms.count) done")
            ChunkyProgressBar(value: ms.isEmpty ? 0 : Double(done) / Double(ms.count), height: 12)
                .padding(.bottom, 4)
            ForEach(ms) { m in
                MilestoneLine(milestone: m) {
                    if let profile = profiles.first {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            ScheduleEngine.complete(m, profile: profile, celebration: celebration)
                        }
                        try? context.save()
                    }
                }
            }
        }
        .card()
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

/// Checkable deadline row (used in detail).
struct MilestoneLine: View {
    let milestone: Milestone
    var onDone: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 14) {
            Button {
                guard !milestone.isDone else { return }
                onDone()
            } label: {
                ZStack {
                    Circle().strokeBorder(milestone.isDone ? accent.base : Theme.tertiary, lineWidth: 2.5)
                    if milestone.isDone {
                        Circle().fill(accent.base)
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(accent.on)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .disabled(milestone.isDone)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(milestone.title).font(.ui(16, .semibold)).foregroundStyle(milestone.isDone ? Theme.secondary : Theme.ink)
                        .strikethrough(milestone.isDone, color: Theme.secondary)
                    if milestone.isLaunch { Image(systemName: "flag.checkered").font(.system(size: 12)).foregroundStyle(accent.text) }
                }
                Text(subtitle).font(.ui(13)).foregroundStyle(milestone.isOverdue ? Theme.danger : Theme.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let done = milestone.completedAt {
            return milestone.completedOnTime ? "Done \(done.dayMonth) · on time" : "Done \(done.dayMonth) · late"
        }
        if milestone.isOverdue { return "Overdue since \(milestone.dueDate.shortDay)" }
        if milestone.isDueToday { return "Due today" }
        return milestone.dueDate.shortDay
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { project.name = trimmed }
                project.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
                project.coverImage = imageData
                project.accentHex = accentHex
                try? context.save()
                Haptics.success()
                dismiss()
            }
            .buttonStyle(.chunky)
            .padding(20)
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
        }
    }
}

struct ConnectionSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var probe: ProbeState = .idle

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connection").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                ConnectionFields(endpoint: $endpoint, apiKey: $apiKey, probe: $probe)
                    .padding(.horizontal, 20)
            }
            Button("Save") {
                project.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
                Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: project.id.uuidString)
                try? context.save()
                Haptics.success()
                Task { await refresher.refresh(projects: [project], context: context, force: true) }
                dismiss()
            }
            .buttonStyle(.chunky)
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .onAppear {
            endpoint = project.endpoint
            apiKey = Keychain.get(project.id.uuidString) ?? ""
        }
    }
}
