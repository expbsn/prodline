import SwiftUI
import SwiftData

/// Plan on the Mac: the agenda (overdue, the picked day, what's coming) next to a month calendar with
/// every project's checkpoints on it, then the next-project countdown and the idea inbox.
struct MacPlanView: View {
    let profile: Profile
    var onOpen: (Project) -> Void
    var onCreate: () -> Void
    var onIdeas: () -> Void
    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @State private var selectedDay = Date.now.startOfDay
    @State private var month = Date.now.startOfDay
    @State private var width: CGFloat = 1000

    private var all: [Milestone] { projects.flatMap { $0.milestones ?? [] }.sorted { $0.dueDate < $1.dueDate } }
    private var overdue: [Milestone] { all.filter(\.isOverdue) }
    private var onSelectedDay: [Milestone] { all.filter { $0.dueDate == selectedDay } }
    private var comingUp: [Milestone] { Array(all.filter { !$0.isDone && $0.dueDate > selectedDay }.prefix(6)) }
    private var nextProject: Date { ScheduleEngine.nextProjectDate(projects: projects, profile: profile) }
    private var wide: Bool { width >= 860 }

    var body: some View {
        MacScroll {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Level \(profile.level) · \(profile.xp) XP").eyebrow().lineLimit(1)
                    Text("Plan").display(44, 750).foregroundStyle(Theme.ink).lineLimit(1)
                }
                if wide {
                    HStack(alignment: .top, spacing: 26) {
                        agenda.frame(maxWidth: .infinity)
                        VStack(spacing: 20) {
                            calendar
                            nextProjectCard
                            IdeaInboxCard(profile: profile, onOpen: onIdeas)
                        }
                        .frame(width: 330)
                    }
                } else {
                    calendar
                    agenda
                    nextProjectCard
                    IdeaInboxCard(profile: profile, onOpen: onIdeas)
                }
            }
            .padding(.horizontal, 40).padding(.top, 34).padding(.bottom, 40)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Theme.background)
    }

    // MARK: Agenda

    private var dayTitle: String {
        if selectedDay == .now.startOfDay { return "Today" }
        if selectedDay == Date.now.startOfDay.adding(days: 1) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !overdue.isEmpty {
                section("Overdue", tint: Theme.danger, overdue)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayTitle).eyebrow().lineLimit(1)
                    Spacer()
                    if selectedDay != .now.startOfDay {
                        Button("Back to today") { pick(.now.startOfDay) }
                            .buttonStyle(.plain).font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
                    }
                }
                if onSelectedDay.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "sun.max.fill").font(.system(size: 22)).foregroundStyle(Color(hex: 0xFFC800))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(projects.isEmpty ? "No deadlines yet" : "Nothing due").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                            Text(projects.isEmpty ? "Create a project to get your first checkpoints." : "A clear day to build.")
                                .font(.ui(13)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        if projects.isEmpty {
                            Button("New project", action: onCreate).buttonStyle(.chunky(.accent, height: 38, fullWidth: false))
                                .environment(\.accent, .neutral)
                        }
                    }
                    .card(padding: 18, radius: 22)
                } else {
                    ForEach(onSelectedDay) { row($0) }
                }
            }
            if !comingUp.isEmpty {
                section("Coming up", tint: Theme.secondary, comingUp)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedDay)
    }

    private func section(_ title: String, tint: Color, _ ms: [Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).eyebrow(tint).lineLimit(1)
            ForEach(ms) { row($0) }
        }
    }

    private func row(_ m: Milestone) -> some View {
        MacDeadlineRow(milestone: m, onOpen: { if let p = m.project { onOpen(p) } }) {
            MacActions.complete(m, profile: profile, projects: projects, celebration: celebration, context: context)
        }
        .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.95).combined(with: .opacity)))
    }

    // MARK: Calendar

    private var calendar: some View {
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: month)?.start ?? month
        let lead = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { monthStart.adding(days: $0) }
        let symbols = cal.veryShortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.display(18, 750)).foregroundStyle(Theme.ink)
                Spacer()
                monthButton("chevron.left") { month = monthStart.adding(days: -1) }
                monthButton("chevron.right") { month = monthStart.adding(days: count) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.ui(11, .semibold)).foregroundStyle(Theme.tertiary).frame(height: 18)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .card(padding: 16, radius: 22)
    }

    private func monthButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary)
                .frame(width: 26, height: 26).background(Circle().fill(Theme.inset))
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = day == selectedDay
        let today = day == .now.startOfDay
        let dots = all.filter { $0.dueDate == day }.compactMap { m in m.project.map { (m.isDone, $0.accent) } }
        return Button { pick(day) } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.ui(13, today || selected ? .bold : .medium))
                    .foregroundStyle(selected ? Theme.inverse : today ? Theme.ink : Theme.inkSoft)
                HStack(spacing: 2) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, d in
                        Circle().fill(selected ? Theme.inverse : d.1.base).opacity(d.0 ? 0.4 : 1).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.ink : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(today && !selected ? Theme.ink : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ day: Date) {
        Haptics.select()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedDay = day
            month = day
        }
    }

    // MARK: Side cards

    private var nextProjectCard: some View {
        let daysLeft = Date.days(from: .now, to: nextProject)
        let due = projects.isEmpty || daysLeft <= 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Next project").eyebrow(size: 11)
            Text(due ? "Time for a new build" : "Starts in \(daysLeft.durationText)")
                .display(22, 750).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
            if due {
                Button("Create project", action: onCreate).buttonStyle(.chunky(.accent, height: 42)).environment(\.accent, .neutral)
            } else {
                ChunkyProgressBar(value: 1 - Double(daysLeft) / Double(max(profile.newProjectEveryDays, 1)), color: Theme.ink, height: 10)
                Text("Planned for \(nextProject.shortDay) · every \(profile.newProjectEveryDays.durationText)")
                    .font(.ui(13)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .card(padding: 18, radius: 22)
    }
}

/// A checkpoint from any project, one line: its project, title, when, goals, and what to do next.
struct MacDeadlineRow: View {
    let milestone: Milestone
    var onOpen: () -> Void
    var onDone: () -> Void
    @State private var hover = false

    var body: some View {
        let accent = milestone.project?.accent ?? .neutral
        HStack(spacing: 14) {
            if let p = milestone.project { ProjectThumb(project: p, size: 44) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(milestone.title).font(.ui(16, .semibold)).foregroundStyle(milestone.isDone ? Theme.secondary : Theme.ink).lineLimit(1)
                    if milestone.isLaunch { Image(systemName: "flag.checkered").font(.system(size: 11)).foregroundStyle(accent.text) }
                }
                Text("\(milestone.project?.name ?? "") · \(when)")
                    .font(.ui(13)).foregroundStyle(milestone.isOverdue ? Theme.danger : Theme.secondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 10)
            if let next = milestone.openGoals.first, !milestone.isDone {
                Label(next.title, systemImage: next.source.symbol)
                    .font(.ui(13, .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            if milestone.isDone {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(accent.base)
            } else if milestone.hasGoals {
                GoalRing(milestone: milestone).help("\(milestone.openGoals.count) goals left")
            } else {
                Button("Done", action: onDone).buttonStyle(.chunky(.accent, height: 36, fullWidth: false))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(hover ? accent.base.opacity(0.5) : .clear, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hover = $0 }
        .environment(\.accent, accent)
    }

    private var when: String {
        if milestone.isDone { return "Done" }
        if milestone.isOverdue { return "was due \(milestone.dueDate.shortDay)" }
        if milestone.isDueToday { return "due today" }
        return milestone.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
