import SwiftUI
import SwiftData

/// The checkpoints in date order, full width, each with its goals underneath (the iPhone's Deadlines
/// card, laid out for a desktop). The next open one is marked; finished ones fold their goals away.
struct MacCheckpointList: View {
    let project: Project
    var onEdit: (Milestone) -> Void
    var onAdd: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        let ms = project.sortedMilestones
        let done = ms.filter(\.isDone).count
        let fromFile = project.followsPlanFile
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Checkpoints").cardTitle(24).foregroundStyle(Theme.ink)
                Text("\(done) of \(ms.count) done").eyebrow(size: 11).lineLimit(1)
                Spacer(minLength: 8)
                if fromFile {
                    Label("Follows prodline.json", systemImage: "doc.text")
                        .font(.ui(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                        .help("Checkpoints and goals follow prodline.json in \(project.githubRepo). Edit the file to change them.")
                } else {
                    Button(action: onAdd) { Label("Add checkpoint", systemImage: "plus") }
                        .buttonStyle(.chunky(.neutral, height: 36, fullWidth: false))
                }
            }
            ChunkyProgressBar(value: ms.isEmpty ? 0 : Double(done) / Double(ms.count), height: 10)

            VStack(spacing: 0) {
                ForEach(Array(ms.enumerated()), id: \.element.id) { i, m in
                    MacCheckpointRow(milestone: m, isNext: m.id == project.nextMilestone?.id, fromFile: fromFile,
                                     onEdit: { onEdit(m) })
                    if i < ms.count - 1 { Divider().padding(.leading, 66) }
                }
                if ms.isEmpty {
                    Text("No checkpoints yet.").font(.ui(14)).foregroundStyle(Theme.secondary).padding(24)
                }
            }
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
        }
    }
}

struct MacCheckpointRow: View {
    let milestone: Milestone
    let isNext: Bool
    let fromFile: Bool
    var onEdit: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var projects: [Project]
    @State private var hover = false
    @State private var showDoneGoals = false
    @State private var newGoal = ""
    @State private var reopening = false
    @FocusState private var addFocused: Bool

    private var m: Milestone { milestone }
    private var goalsVisible: Bool { !m.isDone || showDoneGoals }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    if m.isDone { reopening = true }
                    else { MacActions.complete(m, profile: profiles.first, projects: projects, celebration: celebration, context: context) }
                } label: { CheckpointRing(milestone: m, size: 32) }
                .buttonStyle(PressableStyle(scale: 0.85))
                .disabled(fromFile && m.hasGoals)
                .help(m.isDone ? "Done. Click to reopen" : m.hasGoals ? "Finishes when its goals are done, or click to finish now" : "Mark done")

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(m.title).font(.ui(17, .semibold)).foregroundStyle(m.isDone ? Theme.secondary : Theme.ink).lineLimit(1)
                        if m.isLaunch { Image(systemName: "flag.checkered").font(.system(size: 12)).foregroundStyle(accent.text) }
                        if isNext {
                            Text("Up next").font(.ui(11, .bold)).foregroundStyle(accent.on)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(accent.base))
                        }
                    }
                    Text(subtitle).font(.ui(13)).foregroundStyle(m.isOverdue ? Theme.danger : m.isDueToday ? Theme.flame : Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if m.isDone && m.hasGoals {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showDoneGoals.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\((m.goals ?? []).count) goals")
                            Image(systemName: "chevron.down").rotationEffect(.degrees(showDoneGoals ? 180 : 0))
                        }
                        .font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if !fromFile && !m.isDone {
                    Button(action: onEdit) {
                        Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.inset))
                    }
                    .buttonStyle(.plain)
                    .opacity(hover ? 1 : 0)
                    .help("Edit checkpoint")
                }
                Text(dateBadge).font(.ui(13, .semibold)).foregroundStyle(m.isDone ? Theme.tertiary : Theme.inkSoft)
                    .monospacedDigit().lineLimit(1)
                    .frame(minWidth: 90, alignment: .trailing)
            }

            if goalsVisible && (m.hasGoals || (!m.isDone && !fromFile)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(m.displayGoals) { g in
                        MacGoalRow(goal: g) {
                            MacActions.toggle(g, profile: profiles.first, projects: projects, celebration: celebration, context: context)
                        }
                        .contextMenu {
                            if !g.source.isAutomatic && !fromFile {
                                Button("Delete goal", systemImage: "trash", role: .destructive) {
                                    context.delete(g)
                                    try? context.save()
                                }
                            }
                        }
                    }
                    if !m.isDone && !fromFile { addGoalField }
                }
                .padding(.leading, 46)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(isNext ? accent.soft : hover ? Theme.inset.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .confirmationDialog("Reopen \(m.title)?", isPresented: $reopening, titleVisibility: .visible) {
            Button("Mark as not done", role: .destructive) {
                MacActions.reopen(m, profile: profiles.first, projects: projects, context: context)
            }
        } message: {
            Text(m.xpEarned > 0 ? "You'll lose the \(m.xpEarned) XP it earned." : "It goes back to open.")
        }
    }

    /// Type a goal and press Return; it lands at the end of this checkpoint.
    private var addGoalField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(addFocused ? accent.text : Theme.tertiary)
                .frame(width: 20, height: 20)
            TextField("", text: $newGoal, prompt: Text("Add a goal").foregroundStyle(Theme.tertiary))
                .textFieldStyle(.plain)
                .font(.ui(14, .medium))
                .foregroundStyle(Theme.ink)
                .focused($addFocused)
                .onSubmit {
                    let t = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    GoalEngine.addGoals([t], source: .manual, to: m, context: context)
                    try? context.save()
                    Haptics.success()
                    newGoal = ""
                    addFocused = true
                }
        }
    }

    private var subtitle: String {
        if let done = m.completedAt { return m.completedOnTime ? "Done \(done.dayMonth), on time" : "Done \(done.dayMonth), late" }
        let gs = m.goals ?? []
        let goals = gs.isEmpty ? "No goals yet" : "\(gs.filter(\.isDone).count) of \(gs.count) goals"
        if m.isOverdue { return "Overdue · \(goals)" }
        if m.isDueToday { return "Due today · \(goals)" }
        let d = Date.days(from: .now, to: m.dueDate)
        return "In \(d) day\(d == 1 ? "" : "s") · \(goals)"
    }

    private var dateBadge: String { m.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}
