import SwiftUI
import SwiftData
import AppKit

/// The menu bar icon: the flame with today's streak once there is one.
struct MenuBarLabel: View {
    @Query private var profiles: [Profile]
    var body: some View {
        let streak = profiles.first?.streak ?? 0
        if streak > 0 {
            Label("\(streak)", systemImage: "flame.fill").labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "flame")
        }
    }
}

/// The menu bar window: the next checkpoint across all projects, its goals to tick, and each active
/// project's headline number.
struct MenuBarPanel: View {
    @Query(sort: \Project.startDate, order: .reverse) private var projects: [Project]
    @Query private var profiles: [Profile]
    @Environment(\.openWindow) private var openWindow

    private var active: [Project] { projects.filter(\.isActive) }
    private var next: Milestone? {
        active.compactMap(\.nextMilestone).min { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Prodline").font(.display(18, 750))
                Spacer()
                StreakBadge(streak: profiles.first?.streak ?? 0)
            }

            if let m = next, let p = m.project {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProjectThumb(project: p, size: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.title).font(.system(size: 13, weight: .semibold))
                            Text("\(p.name) · \(due(m))").font(.system(size: 11)).foregroundStyle(m.isOverdue ? Theme.danger : .secondary)
                        }
                    }
                    ForEach(m.displayGoals.prefix(5)) { g in GoalToggle(goal: g, accent: p.accent) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
            } else {
                Text(active.isEmpty ? "No active projects." : "Nothing due. Nice.").foregroundStyle(.secondary)
            }

            if !active.isEmpty {
                VStack(spacing: 6) {
                    ForEach(active) { p in
                        HStack(spacing: 8) {
                            ProjectThumb(project: p, size: 18)
                            Text(p.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(headline(p)).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: { Text("Open Prodline").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink) }
                Spacer()
                Button { NSApp.terminate(nil) } label: { Text("Quit").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func due(_ m: Milestone) -> String {
        if m.isOverdue { return "overdue" }
        if m.isDueToday { return "due today" }
        let d = Date.days(from: .now, to: m.dueDate)
        return d == 1 ? "due tomorrow" : "in \(d) days"
    }

    private func headline(_ p: Project) -> String {
        guard let s = p.latestSnapshot else { return "Day \(p.dayInPhase)" }
        if let key = MetricKey.allCases.max(by: { s.value($0) < s.value($1) }), s.value(key) > 0 { return key.format(s.value(key)) + " " + key.title.lowercased() }
        return "Day \(p.dayInPhase)"
    }
}

/// A goal with the iPhone app's round check.
struct GoalToggle: View {
    @Bindable var goal: Goal
    let accent: Accent
    @State private var hover = false

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { goal.setDone(!goal.isDone) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(goal.isDone ? accent.base : Theme.tertiary, lineWidth: 1.5)
                        .background(Circle().fill(goal.isDone ? accent.base : hover ? accent.soft : .clear))
                    if goal.isDone {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(accent.on)
                    }
                }
                .frame(width: 18, height: 18)
                Text(goal.title).strikethrough(goal.isDone).foregroundStyle(goal.isDone ? Theme.secondary : Theme.ink)
                    .lineLimit(1)
                if goal.source.isAutomatic {
                    Image(systemName: goal.source.symbol).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                        .help("Ticks itself: \(goal.source.label)")
                }
            }
            .font(.ui(13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(goal.source.isAutomatic)
        .onHover { hover = $0 }
    }
}
