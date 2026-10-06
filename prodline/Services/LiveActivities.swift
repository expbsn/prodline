import Foundation
import ActivityKit

/// Puts a checkpoint that's due today on the Lock Screen and in the Dynamic Island, but only while it
/// still has open goals. Ticking the last goal shows a short "all done" and lets it go.
///
/// iOS only lets the app start one while it's open, and ends any after 8 hours. So it appears the
/// first time Prodline is opened on the deadline day, and comes back on a later open if the system
/// ended it. If the user swiped it away, it stays away for that checkpoint.
enum LiveActivities {
    static let enabledKey = "config.liveActivity"
    /// milestone id → when its activity was started.
    private static let startedKey = "liveActivity.started"
    private static let systemLimit: TimeInterval = 7.5 * 3600
    static let maxGoals = 3

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Checkpoints that deserve one right now.
    static func candidates(_ projects: [Project], now: Date = .now) -> [(Project, Milestone)] {
        projects.flatMap { p in
            p.sortedMilestones
                .filter { !$0.isDone && $0.dueDate == now.startOfDay && !$0.openGoals.isEmpty }
                .map { (p, $0) }
        }
    }

    static func state(_ m: Milestone) -> DeadlineAttributes.ContentState {
        let goals = m.displayGoals
        return .init(goals: goals.prefix(maxGoals).map { WidgetGoal(title: $0.title, done: $0.isDone) },
                     goalCount: goals.count, goalsDone: goals.filter(\.isDone).count)
    }

    @MainActor
    static func sync(_ projects: [Project], now: Date = .now) async {
        let running = Activity<DeadlineAttributes>.activities.filter { $0.attributes.projectID != "demo" }
        let wanted = isEnabled ? candidates(projects, now: now) : []
        let wantedIDs = Set(wanted.map { $0.1.id.uuidString })

        for activity in running where !wantedIDs.contains(activity.attributes.milestoneID) {
            await end(activity, projects: projects, now: now)
        }

        var started = UserDefaults.standard.dictionary(forKey: startedKey) as? [String: Date] ?? [:]
        started = started.filter { now.timeIntervalSince($0.value) < 36 * 3600 }
        for (p, m) in wanted {
            let id = m.id.uuidString
            let content = ActivityContent(state: state(m), staleDate: m.dueDate.adding(days: 1))
            if let activity = running.first(where: { $0.attributes.milestoneID == id }) {
                if activity.content.state != content.state { await activity.update(content) }
                continue
            }
            // Gone before the system's 8 hours were up: the user dismissed it.
            if let at = started[id], now.timeIntervalSince(at) < systemLimit { continue }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { continue }
            let attributes = DeadlineAttributes(projectID: p.id.uuidString, milestoneID: id, projectName: p.name,
                                                accentHex: p.accentHex, checkpoint: m.title, due: m.dueDate)
            if (try? Activity.request(attributes: attributes, content: content)) != nil { started[id] = now }
        }
        UserDefaults.standard.set(started, forKey: startedKey)
    }

    /// Finished: show it done for a few minutes. Anything else (day over, checkpoint moved or deleted): gone now.
    @MainActor
    private static func end(_ activity: Activity<DeadlineAttributes>, projects: [Project], now: Date) async {
        let m = projects.lazy.flatMap { $0.milestones ?? [] }.first { $0.id.uuidString == activity.attributes.milestoneID }
        if let m, m.dueDate >= now.startOfDay, m.isDone || m.openGoals.isEmpty, m.hasGoals {
            var final = state(m)
            final.goalsDone = final.goalCount
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(now.addingTimeInterval(5 * 60)))
        } else {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    static func endAll() async {
        for activity in Activity<DeadlineAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    #if DEBUG
    /// -PRODLINE_LIVE: a sample activity, to look at the layout without waiting for a deadline day.
    @MainActor
    static func demo() async {
        let attributes = DeadlineAttributes(projectID: "demo", milestoneID: "demo", projectName: "Habit Hero",
                                            accentHex: 0x58CC02, checkpoint: "Streak screen", due: .now)
        let state = DeadlineAttributes.ContentState(
            goals: [WidgetGoal(title: "Shareable streak card", done: false), WidgetGoal(title: "Push reminders", done: false),
                    WidgetGoal(title: "Onboarding flow live", done: true)],
            goalCount: 4, goalsDone: 1)
        do { _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil)); print("LIVE started") }
        catch { print("LIVE failed: \(error)") }
    }
    #endif
}
