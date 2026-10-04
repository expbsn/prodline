import SwiftUI
import SwiftData

/// Deadlines across all projects: day strip, overdue, the selected day, and the next-project countdown.
struct PlanView: View {
    let profile: Profile
    var onOpen: (Project) -> Void
    var onCreate: () -> Void

    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @State private var selectedDay = Date.now.startOfDay

    private var open: [Milestone] {
        projects.flatMap { $0.milestones ?? [] }.sorted { $0.dueDate < $1.dueDate }
    }
    private var overdue: [Milestone] { open.filter(\.isOverdue) }
    private var onSelectedDay: [Milestone] { open.filter { $0.dueDate == selectedDay } }
    private var comingUp: [Milestone] {
        Array(open.filter { !$0.isDone && $0.dueDate > selectedDay }.prefix(4))
    }
    private var days: [Date] { (-1...12).map { Date.now.startOfDay.adding(days: $0) } }
    private var nextProject: Date { ScheduleEngine.nextProjectDate(projects: projects, profile: profile) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(eyebrow: "Level \(profile.level) · \(profile.xp) XP", title: "Plan")

                statsRow.padding(.horizontal, 16)
                dayStrip

                VStack(alignment: .leading, spacing: 12) {
                    if !overdue.isEmpty {
                        Text("Overdue").eyebrow(Theme.danger)
                        ForEach(overdue) { row($0) }
                    }
                    Text(dayTitle).eyebrow().padding(.top, overdue.isEmpty ? 0 : 8)
                    if onSelectedDay.isEmpty {
                        emptyDay
                    } else {
                        ForEach(onSelectedDay) { row($0) }
                    }
                    if !comingUp.isEmpty {
                        Text("Coming up").eyebrow().padding(.top, 8)
                        ForEach(comingUp) { row($0) }
                    }
                }
                .padding(.horizontal, 16)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedDay)

                nextProjectCard.padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: Pieces

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat(symbol: "flame.fill", tint: Theme.flame, value: "\(profile.streak)", title: "Streak")
            stat(symbol: "star.fill", tint: Color(hex: 0xFFC800), value: "\(profile.xp)", title: "XP")
            stat(symbol: "checkmark.seal.fill", tint: Theme.success,
                 value: profile.onTimeRate.map { "\(Int($0 * 100))%" } ?? "–", title: "On time")
        }
    }

    private func stat(symbol: String, tint: Color, value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint)
            Text(value).display(26, 750).foregroundStyle(Theme.ink).contentTransition(.numericText())
            Text(title).font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
        }
        .card(padding: 14, radius: 22)
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let selected = day == selectedDay
                        let dots = open.filter { $0.dueDate == day && !$0.isDone }.compactMap { $0.project?.accent }
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedDay = day }
                        } label: {
                            VStack(spacing: 6) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.ui(12, .semibold)).textCase(.uppercase)
                                Text(day.formatted(.dateTime.day()))
                                    .display(24, 750)
                                HStack(spacing: 3) {
                                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, a in
                                        Circle().fill(selected ? .white : a.base).frame(width: 6, height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                            .foregroundStyle(selected ? .white : (day == .now.startOfDay ? Theme.ink : Theme.secondary))
                            .frame(width: 56, height: 86)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(selected ? Theme.ink : .white))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(day == .now.startOfDay && !selected ? Theme.ink : .clear, lineWidth: 2))
                        }
                        .buttonStyle(PressableStyle(scale: 0.92))
                        .id(day)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { proxy.scrollTo(Date.now.startOfDay.adding(days: -1), anchor: .leading) }
        }
    }

    private var dayTitle: String {
        if selectedDay == .now.startOfDay { return "Today" }
        if selectedDay == Date.now.startOfDay.adding(days: 1) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var emptyDay: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.fill").font(.system(size: 24)).foregroundStyle(Color(hex: 0xFFC800))
            VStack(alignment: .leading, spacing: 2) {
                Text(projects.isEmpty ? "No deadlines yet" : "Nothing due").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                Text(projects.isEmpty ? "Create a project to get your first checkpoints." : "A clear day to build.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
            }
        }
        .card()
    }

    private func row(_ m: Milestone) -> some View {
        DeadlineRow(milestone: m, onOpen: { if let p = m.project { onOpen(p) } }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                ScheduleEngine.complete(m, profile: profile, celebration: celebration)
            }
            try? context.save()
        }
        .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
    }

    private var nextProjectCard: some View {
        let daysLeft = Date.days(from: .now, to: nextProject)
        let due = projects.isEmpty || daysLeft <= 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Next project").eyebrow()
            Text(due ? "It's time to start a new build" : "Starts in \(daysLeft.durationText)")
                .display(26, 750).foregroundStyle(Theme.ink)
            if due {
                Button("Create project", action: onCreate).buttonStyle(.chunky)
            } else {
                ChunkyProgressBar(value: 1 - Double(daysLeft) / Double(max(profile.newProjectEveryDays, 1)),
                                  color: Theme.ink, height: 12)
                Text("Planned for \(nextProject.shortDay) · every \(profile.newProjectEveryDays.durationText)")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
            }
        }
        .card()
    }
}

/// Cross-project deadline row; colored by its project.
struct DeadlineRow: View {
    let milestone: Milestone
    var onOpen: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let p = milestone.project {
                Button(action: onOpen) { ProjectThumb(project: p, size: 52) }.buttonStyle(PressableStyle(scale: 0.92))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(milestone.title).font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                Text("\(milestone.project?.name ?? "") · \(subtitle)")
                    .font(.ui(13)).foregroundStyle(milestone.isOverdue ? Theme.danger : Theme.secondary)
                    .lineLimit(1)
                if let next = milestone.openGoals.first {
                    Label(next.title, systemImage: next.source.symbol)
                        .font(.ui(13, .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if milestone.isDone {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28))
                    .foregroundStyle(milestone.project?.accent.base ?? Theme.success)
            } else if milestone.hasGoals {
                // Goal-driven checkpoints complete themselves; open the project to work the list.
                Button(action: onOpen) { GoalRing(milestone: milestone) }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityLabel("\(milestone.openGoals.count) goals left")
            } else {
                Button("Done", action: onDone)
                    .buttonStyle(.chunky(.accent, height: 42, fullWidth: false))
            }
        }
        .card(padding: 12, radius: 24)
        .environment(\.accent, milestone.project?.accent ?? .neutral)
    }

    private var subtitle: String {
        if milestone.isDone { return "Done" }
        if milestone.isOverdue { return "was due \(milestone.dueDate.shortDay)" }
        if milestone.isDueToday { return "Due today" }
        return milestone.dueDate.shortDay
    }
}

/// Done / total goals as a ring with the count in the middle.
struct GoalRing: View {
    let milestone: Milestone
    @Environment(\.accent) private var accent

    var body: some View {
        let gs = milestone.goals ?? []
        let done = gs.filter(\.isDone).count
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 4)
            Circle().trim(from: 0, to: gs.isEmpty ? 0 : Double(done) / Double(gs.count))
                .stroke(accent.base, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(gs.count)").font(.display(14, 750)).foregroundStyle(Theme.ink)
        }
        .frame(width: 46, height: 46)
    }
}
