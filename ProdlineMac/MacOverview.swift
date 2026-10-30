import SwiftUI
import SwiftData

/// Dash on the Mac: the numbers that matter in one strip, today's checkpoints to tick beside what happened
/// lately, and every project as its card in a grid.
struct MacOverview: View {
    let profile: Profile
    var onOpen: (Project) -> Void
    var onCreate: () -> Void
    var onReview: () -> Void
    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher
    @State private var width: CGFloat = 1000
    /// Up next and Activity side by side while the window is wide enough for both.
    private var twoColumns: Bool { width >= 880 }

    private var active: [Project] { projects.filter { $0.phase() != .finished }.reversed() }
    private var finished: [Project] { projects.filter { $0.phase() == .finished }.reversed() }
    /// Checkpoints due today or overdue, then the next one of each project that has none of those.
    private var focus: [Milestone] {
        let due = active.flatMap { $0.sortedMilestones.filter { !$0.isDone && ($0.isDueToday || $0.isOverdue) } }
        let next = active.filter { p in !due.contains { $0.project?.id == p.id } }.compactMap(\.nextMilestone)
        return Array((due + next.sorted { $0.dueDate < $1.dueDate }).prefix(4))
    }

    /// The deadlines after the ones in Up next.
    private var comingUp: [Milestone] {
        let shown = Set(focus.map(\.id))
        return active.flatMap(\.sortedMilestones)
            .filter { !$0.isDone && !shown.contains($0.id) && $0.dueDate > Date.now.startOfDay }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(4).map { $0 }
    }

    var body: some View {
        MacScroll {
            VStack(alignment: .leading, spacing: 26) {
                header
                stats
                if twoColumns {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            upNext
                            if !comingUp.isEmpty { comingUpPanel }
                        }
                        .frame(maxWidth: .infinity)
                        MacActivityPanel(projects: projects).frame(width: 330)
                    }
                } else {
                    upNext
                    if !comingUp.isEmpty { comingUpPanel }
                    MacActivityPanel(projects: projects, limit: 6)
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Projects", trailing: "\(active.count) active")
                    cardGrid(active, withCreate: true)
                }
                if !finished.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Finished")
                        cardGrid(finished, withCreate: false)
                    }
                }
            }
            .padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 36)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Theme.background)
    }

    /// The checkpoints to work on, in one panel with their open goals to tick.
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next").cardTitle(20).foregroundStyle(Theme.ink)
                Spacer()
                let due = focus.filter { $0.isDueToday || $0.isOverdue }.count
                Text(due == 0 ? "Nothing due today" : "\(due) due today").eyebrow(size: 10)
            }
            if focus.isEmpty {
                Text("No open checkpoints. Start a project and its plan lands here.")
                    .font(.ui(13)).foregroundStyle(Theme.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(focus.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Divider().overlay(Theme.line).padding(.vertical, 12) }
                        MacFocusRow(milestone: m, onOpen: { if let p = m.project { onOpen(p) } })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 20, radius: 24)
    }

    private var comingUpPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming up").cardTitle(20).foregroundStyle(Theme.ink)
            VStack(spacing: 10) {
                ForEach(comingUp) { m in
                    Button { if let p = m.project { onOpen(p) } } label: {
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Text(m.dueDate.formatted(.dateTime.weekday(.abbreviated))).font(.ui(10, .bold)).textCase(.uppercase)
                                    .foregroundStyle(Theme.secondary)
                                Text(m.dueDate.formatted(.dateTime.day())).display(18, 750).foregroundStyle(Theme.ink)
                            }
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.background))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.ui(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(m.project?.name ?? "").font(.ui(12)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            let days = Date.days(from: Date.now.startOfDay, to: m.dueDate)
                            Text(days == 1 ? "Tomorrow" : "In \(days) days").font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 20, radius: 24)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var header: some View {
        // Buttons beside the greeting while there's room, under it when the window is narrow.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                greetingBlock
                Spacer(minLength: 16)
                headerButtons
            }
            VStack(alignment: .leading, spacing: 18) {
                greetingBlock
                headerButtons
            }
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).eyebrow().lineLimit(1)
            Text(greeting).display(38, 750).foregroundStyle(Theme.ink).lineLimit(1).fixedSize()
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 10) {
            // Like on the iPhone: only from Sunday evening until the wrap is watched, in the week chip's gold.
            if WeeklyReview.isWaiting() {
                Button {
                    Haptics.select()
                    onReview()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(Accent.sale.text)
                        Text("Weekly wrap")
                            .display(15, 700).tracking(1.2).textCase(.uppercase)
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0xFFC800), lineWidth: 2.5))
                    .shadow(color: Color(hex: 0xFFC800).opacity(0.45), radius: 10)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .transition(.scale.combined(with: .opacity))
            }
            Button(action: onCreate) { Label("New project", systemImage: "plus") }
                .buttonStyle(.chunky(.accent, height: 42, fullWidth: false))
                .environment(\.accent, .neutral)
        }
        .fixedSize()
    }

    /// The four headline numbers in one strip; two by two when the window is narrow.
    private var stats: some View {
        let ms = active.flatMap(\.sortedMilestones)
        let today = Date.now.startOfDay
        let onTime = profile.onTimeRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        let streak = MacStatCell(title: "Streak", value: "\(profile.streak)", detail: profile.streak == 1 ? "day" : "days") {
            FlameMark(color: Theme.flame, lit: profile.streakActiveToday == today).frame(width: 24)
        }
        let level = MacStatCell(title: "Level \(profile.level)", value: "\(profile.xp)", detail: "XP") {
            ChunkyProgressBar(value: profile.levelProgress, color: Theme.brand, height: 8).frame(width: 64)
        }
        let checkpoints = MacStatCell(title: "Checkpoints", value: "\(ms.filter(\.isDone).count)/\(ms.count)", detail: "done") {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.success)
        }
        let onTimeCell = MacStatCell(title: "On time", value: onTime, detail: "of checkpoints") {
            Image(systemName: "clock.fill").font(.system(size: 20)).foregroundStyle(Theme.secondary)
        }
        let divider = Rectangle().fill(Theme.line).frame(width: 1).padding(.vertical, 4)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                streak; divider; level; divider; checkpoints; divider; onTimeCell
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 760)
            Grid(horizontalSpacing: 22, verticalSpacing: 18) {
                GridRow { streak; level }
                GridRow { checkpoints; onTimeCell }
            }
        }
        .card(padding: 20, radius: 24)
    }

    private func cardGrid(_ ps: [Project], withCreate: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
            ForEach(ps) { p in MacProjectTile(project: p) { onOpen(p) } }
            if withCreate {
                Button(action: onCreate) {
                    VStack(alignment: .leading, spacing: 12) {
                        CreateProjectCardFace(subtitle: "\(profile.buildDays)d build · \(profile.observeDays)d observe")
                        Text("Start something new").font(.ui(13)).foregroundStyle(Theme.secondary)
                    }
                }
                .buttonStyle(MacLiftStyle())
            }
        }
    }
}

/// One headline number in the stats strip.
struct MacStatCell<Accessory: View>: View {
    let title: String
    let value: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).eyebrow(size: 10).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).display(28, 750).foregroundStyle(Theme.ink).contentTransition(.numericText())
                        .lineLimit(1).fixedSize()
                    Text(detail).font(.ui(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .frame(maxWidth: .infinity)
    }
}

/// A project as its card, with where it stands underneath; lifts on hover.
struct MacProjectTile: View {
    let project: Project
    var onOpen: () -> Void
    @Environment(DataRefresher.self) private var refresher

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                ProjectCardFace(project: project, refresher: refresher)
                VStack(alignment: .leading, spacing: 4) {
                    if let m = project.nextMilestone {
                        HStack(spacing: 6) {
                            Circle().fill(m.isOverdue ? Theme.danger : m.isDueToday ? Theme.flame : project.accent.base)
                                .frame(width: 7, height: 7)
                            Text(m.title).font(.ui(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        }
                        Text(m.macSubtitle).font(.ui(12)).foregroundStyle(m.isOverdue ? Theme.danger : Theme.secondary).lineLimit(1)
                    } else {
                        Text(project.phase() == .finished ? (project.verdict?.pastTense ?? "Decision time") : "All checkpoints done")
                            .font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(MacLiftStyle())
    }
}

/// Hover lifts a card a little, pressing pushes it back down.
struct MacLiftStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacLiftBody(configuration: configuration)
    }

    private struct MacLiftBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : hover ? 1.025 : 1)
                .offset(y: hover && !configuration.isPressed ? -4 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}

/// The next checkpoint of a project, with its open goals to tick right here.
struct MacFocusRow: View {
    let milestone: Milestone
    var onOpen: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var projects: [Project]

    var body: some View {
        let accent = milestone.project?.accent ?? .neutral
        let open = milestone.openGoals
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        if let p = milestone.project { ProjectThumb(project: p, size: 34) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.title).cardTitle(17).foregroundStyle(Theme.ink).lineLimit(1)
                            Text("\(milestone.project?.name ?? "") · \(milestone.macSubtitle)")
                                .font(.ui(12, .medium)).lineLimit(1)
                                .foregroundStyle(milestone.isOverdue ? Theme.danger : milestone.isDueToday ? Theme.flame : Theme.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(milestone.project?.name ?? "project")")
                Spacer(minLength: 8)
                if milestone.hasGoals {
                    CheckpointRing(milestone: milestone, size: 26)
                } else {
                    Button("Mark done") {
                        MacActions.complete(milestone, profile: profiles.first, projects: projects, celebration: celebration, context: context)
                    }
                    .buttonStyle(.chunky(.accent, height: 32, fullWidth: false))
                }
            }
            if !open.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(open.prefix(3)) { g in
                        MacGoalRow(goal: g, compact: true) {
                            MacActions.toggle(g, profile: profiles.first, projects: projects, celebration: celebration, context: context)
                        }
                    }
                    if open.count > 3 {
                        Text("+\(open.count - 3) more").font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.leading, 46)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.accent, accent)
    }
}
