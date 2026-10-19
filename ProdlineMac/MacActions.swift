import SwiftUI
import SwiftData

/// Ticking goals and checkpoints on the Mac: the same engines and order as the iPhone's project screen
/// (tick shows at once; XP, the checkpoint, the streak and saving follow).
@MainActor
enum MacActions {
    static func toggle(_ g: Goal, profile: Profile?, projects: [Project], celebration: CelebrationCenter, context: ModelContext) {
        guard !g.source.isAutomatic else { return }
        Haptics.select()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { g.setDone(!g.isDone) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            if let profile, let project = g.milestone?.project {
                GoalEngine.awardGoalXP(projects: [project], profile: profile, celebration: celebration)
                if g.isDone {
                    GoalEngine.autoComplete(projects: [project], profile: profile, celebration: celebration)
                } else if let m = g.milestone, m.isDone {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { ScheduleEngine.uncomplete(m, profile: profile) }
                }
                Streak.refresh(profile, projects: projects, celebration: celebration)
            }
            try? context.save()
        }
    }

    static func complete(_ m: Milestone, profile: Profile?, projects: [Project], celebration: CelebrationCenter, context: ModelContext) {
        guard let profile else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            ScheduleEngine.complete(m, profile: profile, celebration: celebration)
        }
        Streak.refresh(profile, projects: projects, celebration: celebration)
        try? context.save()
    }

    static func reopen(_ m: Milestone, profile: Profile?, projects: [Project], context: ModelContext) {
        guard let profile else { return }
        Haptics.warning()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { ScheduleEngine.uncomplete(m, profile: profile) }
        Streak.update(profile, projects: projects)
        try? context.save()
    }
}

/// A goal with the iPhone's rounded checkbox.
struct MacGoalRow: View {
    let goal: Goal
    var compact = false
    var onToggle: () -> Void
    @Environment(\.accent) private var accent
    @State private var hover = false

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(goal.isDone ? accent.base : hover && !goal.source.isAutomatic ? accent.soft : .clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(goal.isDone ? accent.base : Theme.tertiary, lineWidth: 2)
                    if goal.isDone {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(accent.on)
                    }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.ui(compact ? 13 : 14, .medium))
                        .foregroundStyle(goal.isDone ? Theme.secondary : Theme.ink)
                        .strikethrough(goal.isDone, color: Theme.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(compact ? 1 : 2)
                    if goal.source.isAutomatic && !compact {
                        Label(goal.source.label, systemImage: goal.source.symbol)
                            .font(.ui(11, .medium)).foregroundStyle(Theme.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(goal.source.isAutomatic)
        .onHover { hover = $0 }
        .help(goal.source.isAutomatic ? "Ticks itself: \(goal.source.label)" : "")
    }
}

/// Checkpoint ring: fills with its goals, solid when done.
struct CheckpointRing: View {
    let milestone: Milestone
    var size: CGFloat = 30
    @Environment(\.accent) private var accent

    private var progress: Double {
        let gs = milestone.goals ?? []
        return gs.isEmpty ? 0 : Double(gs.filter(\.isDone).count) / Double(gs.count)
    }

    var body: some View {
        ZStack {
            if milestone.hasGoals && !milestone.isDone {
                Circle().stroke(accent.tint, lineWidth: size * 0.1)
                Circle().trim(from: 0, to: progress)
                    .stroke(accent.base, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().strokeBorder(milestone.isDone ? accent.base : milestone.isOverdue ? Theme.danger : accent.base.opacity(0.45),
                                      lineWidth: size * 0.083)
            }
            if milestone.isDone {
                Circle().fill(accent.base)
                Image(systemName: "checkmark").font(.system(size: size * 0.43, weight: .heavy)).foregroundStyle(accent.on)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
    }
}

extension Milestone {
    /// "Due today · 2/3 goals", as on the iPhone.
    var macSubtitle: String {
        if let done = completedAt {
            return completedOnTime ? "Done \(done.dayMonth) · on time" : "Done \(done.dayMonth) · late"
        }
        var s = isOverdue ? "Overdue since \(dueDate.shortDay)" : isDueToday ? "Due today" : dueDate.shortDay
        if hasGoals {
            let gs = goals ?? []
            s += " · \(gs.filter(\.isDone).count)/\(gs.count) goals"
        }
        return s
    }
}

extension EnvironmentValues {
    /// DEBUG snapshots render whole pages, which a ScrollView would clip to nothing.
    @Entry var macSnapshot: Bool = false
}

/// A vertical ScrollView, or just its content for a snapshot.
struct MacScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.macSnapshot) private var snapshot
    var body: some View {
        if snapshot { content } else { ScrollView { content } }
    }
}
