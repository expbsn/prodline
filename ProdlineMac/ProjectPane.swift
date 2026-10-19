import SwiftUI
import SwiftData
import AppKit

/// One project: the cover as a wide header, its numbers, the timeline and the checkpoints with goals.
struct ProjectPane: View {
    @Bindable var project: Project

    var body: some View {
        ScrollView {
            content
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(project.name)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            metrics
            timeline
            checkpoints
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = project.coverImage, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [project.accent.base, project.accent.dark], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 6) {
                Label(project.phase().title + (project.isActive ? " · day \(project.dayInPhase) of \(project.phaseLength)" : ""),
                      systemImage: project.phase().symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(project.name).font(.display(40, 750)).foregroundStyle(.white)
                if !project.details.isEmpty {
                    Text(project.details).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                }
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var metricValues: [(String, Double)] {
        guard let s = project.latestSnapshot else { return [] }
        var out: [(String, Double)] = MetricKey.allCases.map { ($0.rawValue, s.value($0)) }.filter { $0.1 > 0 }
        out += s.extras.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return out
    }

    @ViewBuilder
    private var metrics: some View {
        let values = metricValues
        if !values.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(values, id: \.0) { key, value in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MetricKey(rawValue: key)?.title ?? IntegrationMetric.title(key)).eyebrow(size: 10)
                        Text(MetricKey(rawValue: key)?.format(value) ?? IntegrationMetric.format(key, value))
                            .font(.display(28, 700)).foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
            }
            if let at = project.latestSnapshot?.date {
                Text("Updated \(at.formatted(.relative(presentation: .named))) from your iPhone")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timeline").font(.display(20, 700))
                Spacer()
                Text("\(project.startDate.dayMonth) → \(project.launchDay.dayMonth) → \(project.observeEnd.dayMonth)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TimelineBar(project: project)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }

    private var checkpoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Checkpoints").font(.display(20, 700))
            ForEach(project.sortedMilestones) { m in CheckpointRow(milestone: m, accent: project.accent) }
            if project.sortedMilestones.isEmpty {
                Text("No checkpoints yet.").foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

struct CheckpointRow: View {
    @Bindable var milestone: Milestone
    let accent: Accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: milestone.isDone ? "checkmark.circle.fill" : milestone.isOverdue ? "exclamationmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(milestone.isDone ? Theme.success : milestone.isOverdue ? Theme.danger : accent.text)
                Text(milestone.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(milestone.isDueToday ? "Today" : milestone.dueDate.shortDay).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(milestone.displayGoals) { g in GoalToggle(goal: g, accent: accent).padding(.leading, 26) }
        }
        .padding(.vertical, 4)
    }
}

struct GoalToggle: View {
    @Bindable var goal: Goal
    let accent: Accent
    @State private var hover = false

    var body: some View {
        Button {
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
                if goal.source.isAutomatic {
                    Image(systemName: goal.source.symbol).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                        .help("Ticks itself: \(goal.source.label)")
                }
            }
            .font(.system(size: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(goal.source.isAutomatic)
        .onHover { hover = $0 }
    }
}

/// Build and observe as two segments, filled up to today, with a marker on launch day.
struct TimelineBar: View {
    let project: Project

    var body: some View {
        GeometryReader { geo in
            let total = Double(project.buildDays + project.observeDays)
            let buildW = geo.size.width * project.buildDays.double / total
            let done = geo.size.width * min(max(project.overallProgress, 0), 1)
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    Capsule().fill(project.accent.tint).frame(width: max(buildW - 1.5, 0))
                    Capsule().fill(project.accent.soft)
                }
                Capsule().fill(project.accent.base).frame(width: max(done, 8))
                Capsule().fill(Theme.ink).frame(width: 3, height: 18).offset(x: min(max(done - 1.5, 0), geo.size.width - 3))
            }
            .frame(height: 10)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
    }
}

private extension Int { var double: Double { Double(self) } }
