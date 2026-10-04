import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]
    @State private var showAdd = false

    private var openMilestones: [Milestone] {
        projects.flatMap { $0.milestones ?? [] }.filter { !$0.isDone }.sorted { $0.dueDate < $1.dueDate }
    }
    private var dueNow: [Milestone] { openMilestones.filter { $0.isDueToday || $0.isOverdue } }
    private var upcoming: [Milestone] {
        openMilestones.filter { $0.dueDate > .now.startOfDay && $0.dueDate <= Date.now.adding(days: 8) }
    }
    private var nextProjectDate: Date { ScheduleEngine.nextProjectDate(projects: projects, profile: profile) }
    private var daysToNextProject: Int { Date.days(from: .now, to: nextProjectDate) }

    private var totals: (visits: Double, social: Double, revenue: Double) {
        projects.compactMap { refresher.current(for: $0) }
            .reduce((0, 0, 0)) { ($0.0 + $1.visits, $0.1 + $1.social, $0.2 + $1.revenue) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    totalsCard
                    dueSection
                    nextProjectCard
                    if !upcoming.isEmpty { upcomingSection }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await refresher.refresh(projects: projects, context: context, force: true) }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddProjectSheet(profile: profile) }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Pip(size: 64, cheering: dueNow.isEmpty)
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(.display(24)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.rounded(15, .semibold)).foregroundStyle(Theme.inkLight)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                StatPill(icon: "🔥", value: "\(profile.streak)", color: Theme.orange)
                StatPill(icon: "⭐️", value: "\(profile.xp) XP", color: Theme.yellow)
                Spacer(minLength: 0)
                Text("Lv \(profile.level)").font(.rounded(15, .heavy)).foregroundStyle(Theme.blue)
            }
            ChunkyProgressBar(value: profile.levelProgress, color: Theme.blue, height: 14)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning!"
        case 12..<18: "Good afternoon!"
        default: "Good evening!"
        }
    }

    private var subtitle: String {
        if projects.isEmpty { return "Let's start your first project" }
        if dueNow.isEmpty { return "Nothing due today. Nice!" }
        return "\(dueNow.count) deadline\(dueNow.count == 1 ? "" : "s") to hit today"
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Live totals")
                if refresher.isRefreshing {
                    ProgressView().tint(Theme.blue)
                } else if let last = refresher.lastRefresh {
                    Text("updated ").font(.rounded(12, .semibold)).foregroundStyle(Theme.inkLight)
                    + Text(last, style: .relative).font(.rounded(12, .semibold)).foregroundStyle(Theme.inkLight)
                }
            }
            HStack(spacing: 10) {
                totalTile(.visits, totals.visits)
                totalTile(.socialViews, totals.social)
                totalTile(.revenue, totals.revenue)
            }
        }
    }

    private func totalTile(_ key: MetricKey, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(key.icon).font(.system(size: 22))
            Text(key.format(value)).font(.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6).lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(key.title).font(.rounded(11, .bold)).foregroundStyle(Theme.inkLight)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }

    private var dueSection: some View {
        VStack(spacing: 12) {
            SectionTitle("Today")
            if dueNow.isEmpty {
                VStack(spacing: 8) {
                    Text("🎯").font(.system(size: 36))
                    Text(projects.isEmpty ? "Add a project to get your first deadline." : "You're all caught up.")
                        .font(.rounded(16, .bold)).foregroundStyle(Theme.inkLight)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .card()
            } else {
                ForEach(dueNow) { m in
                    MilestoneCard(milestone: m) {
                        ScheduleEngine.complete(m, profile: profile, celebration: celebration)
                        try? context.save()
                    }
                    .transition(.asymmetric(insertion: .scale, removal: .scale.combined(with: .opacity)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: dueNow.map(\.id))
    }

    private var nextProjectCard: some View {
        let due = projects.isEmpty || daysToNextProject <= 0
        return VStack(alignment: .leading, spacing: 12) {
            Text(due ? "Time for a new project! 🚀" : "Next project in \(daysToNextProject.durationText)")
                .font(.rounded(18, .heavy)).foregroundStyle(due ? Theme.blue : Theme.ink)
            Text(due ? "Your \(profile.newProjectEveryDays.durationText) rhythm says it's go time."
                     : "Starts \(nextProjectDate.shortDay). Finish current checkpoints to stay on track.")
                .font(.rounded(14, .semibold)).foregroundStyle(Theme.inkLight)
            if due {
                Button("Start project") { showAdd = true }.buttonStyle(.chunky)
            } else {
                let total = Double(profile.newProjectEveryDays)
                ChunkyProgressBar(value: 1 - Double(daysToNextProject) / max(total, 1), color: Theme.blue, height: 12)
            }
        }
        .padding(16)
        .card(tint: due ? Theme.blue : Theme.line, fill: due ? Theme.blueTint.opacity(0.5) : .white)
    }

    private var upcomingSection: some View {
        VStack(spacing: 10) {
            SectionTitle("Coming up")
            ForEach(upcoming) { m in MilestoneCard(milestone: m, onDone: nil) }
        }
    }
}

struct MilestoneCard: View {
    let milestone: Milestone
    var onDone: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(milestone.project?.emoji ?? "🚀")
                .font(.system(size: 26))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill((milestone.project?.color ?? Theme.blue).opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(milestone.title).font(.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                Text("\(milestone.project?.name ?? "") · \(subtitle)")
                    .font(.rounded(13, .semibold))
                    .foregroundStyle(milestone.isOverdue ? Theme.red : Theme.inkLight)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onDone, !milestone.isDone {
                Button("Done", action: onDone)
                    .buttonStyle(.chunky(.success, height: 40, fullWidth: false))
            } else if milestone.isDone {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.green)
            }
        }
        .padding(12)
        .card(tint: milestone.isOverdue ? Theme.red.opacity(0.5) : Theme.line)
    }

    private var subtitle: String {
        if milestone.isDone { return "Done" }
        if milestone.isOverdue { return "Overdue · \(milestone.dueDate.shortDay)" }
        if milestone.isDueToday { return "Due today" }
        return "Due \(milestone.dueDate.shortDay)"
    }
}
