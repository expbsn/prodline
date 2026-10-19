import SwiftUI
import SwiftData

/// Dash on the Mac: the numbers that matter today across the top, today's checkpoints to tick, and every
/// project as its card in a grid.
struct MacOverview: View {
    let profile: Profile
    var onOpen: (Project) -> Void
    var onCreate: () -> Void
    var onReview: () -> Void
    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher

    private var active: [Project] { projects.filter { $0.phase() != .finished }.reversed() }
    private var finished: [Project] { projects.filter { $0.phase() == .finished }.reversed() }
    /// Checkpoints due today or overdue, then the next one of each project that has none of those.
    private var focus: [Milestone] {
        let due = active.flatMap { $0.sortedMilestones.filter { !$0.isDone && ($0.isDueToday || $0.isOverdue) } }
        let next = active.filter { p in !due.contains { $0.project?.id == p.id } }.compactMap(\.nextMilestone)
        return Array((due + next.sorted { $0.dueDate < $1.dueDate }).prefix(6))
    }

    var body: some View {
        MacScroll {
            VStack(alignment: .leading, spacing: 34) {
                header
                stats
                if !focus.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Up next", trailing: "\(focus.filter { $0.isDueToday || $0.isOverdue }.count) due today")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                            ForEach(focus) { m in MacFocusCard(milestone: m, onOpen: { if let p = m.project { onOpen(p) } }) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    SectionTitle("Projects", trailing: "\(active.count) active")
                    cardGrid(active, withCreate: true)
                }
                if !finished.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle("Finished")
                        cardGrid(finished, withCreate: false)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 34).padding(.bottom, 40)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
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
            Text(greeting).display(44, 750).foregroundStyle(Theme.ink).lineLimit(1).fixedSize()
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 10) {
            Button(action: onReview) { Label("Weekly wrap", systemImage: "play.rectangle.fill") }
                .buttonStyle(.chunky(.neutral, height: 42, fullWidth: false))
            Button(action: onCreate) { Label("New project", systemImage: "plus") }
                .buttonStyle(.chunky(.accent, height: 42, fullWidth: false))
                .environment(\.accent, .neutral)
        }
        .fixedSize()
    }

    private var stats: some View {
        let ms = active.flatMap(\.sortedMilestones)
        let today = Date.now.startOfDay
        let onTime = profile.onTimeRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
            MacStatCard(title: "Streak", value: "\(profile.streak)", detail: profile.streak == 1 ? "day" : "days",
                        tint: Theme.flame) {
                FlameMark(color: Theme.flame, lit: profile.streakActiveToday == today).frame(width: 26)
            }
            MacStatCard(title: "Level \(profile.level)", value: "\(profile.xp)", detail: "XP", tint: Accent(hex: 0x5B5BF0).base) {
                ChunkyProgressBar(value: profile.levelProgress, color: Accent(hex: 0x5B5BF0).base, height: 10).frame(width: 90)
            }
            MacStatCard(title: "Checkpoints", value: "\(ms.filter(\.isDone).count)/\(ms.count)", detail: "done",
                        tint: Theme.success) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.success)
            }
            MacStatCard(title: "On time", value: onTime, detail: "of checkpoints", tint: Theme.ink) {
                Image(systemName: "clock.fill").font(.system(size: 22)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func cardGrid(_ ps: [Project], withCreate: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), spacing: 26, alignment: .top)], alignment: .leading, spacing: 32) {
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

/// One headline number in a card.
struct MacStatCard<Accessory: View>: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).eyebrow(size: 11).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).display(32, 750).foregroundStyle(Theme.ink).contentTransition(.numericText())
                        .lineLimit(1).fixedSize()
                    Text(detail).font(.ui(13, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .card(padding: 20, radius: 24)
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

/// The next checkpoint of a project, with its goals to tick right here.
struct MacFocusCard: View {
    let milestone: Milestone
    var onOpen: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var projects: [Project]

    var body: some View {
        let accent = milestone.project?.accent ?? .neutral
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        if let p = milestone.project { ProjectThumb(project: p, size: 40) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.project?.name ?? "").eyebrow(size: 10).lineLimit(1)
                            Text(milestone.title).display(20, 750).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(milestone.project?.name ?? "project")")
                Spacer(minLength: 8)
                CheckpointRing(milestone: milestone, size: 30)
            }
            Text(milestone.macSubtitle)
                .lineLimit(1)
                .font(.ui(13, .semibold))
                .foregroundStyle(milestone.isOverdue ? Theme.danger : milestone.isDueToday ? Theme.flame : Theme.secondary)
            if milestone.hasGoals {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(milestone.displayGoals.prefix(5)) { g in
                        MacGoalRow(goal: g, compact: true) {
                            MacActions.toggle(g, profile: profiles.first, projects: projects, celebration: celebration, context: context)
                        }
                    }
                    if (milestone.goals ?? []).count > 5 {
                        Text("+\((milestone.goals ?? []).count - 5) more").font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
                    }
                }
            } else {
                Button("Mark done") {
                    MacActions.complete(milestone, profile: profiles.first, projects: projects, celebration: celebration, context: context)
                }
                .buttonStyle(.chunky(.accent, height: 38))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 20, radius: 24)
        .environment(\.accent, accent)
    }
}
