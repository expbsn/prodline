import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Checkpoints")
struct CheckpointTests {
    /// Monday Jan 5 2026, 14-day build, Mon+Fri checkpoints → [CP1 Fri 9, CP2 Mon 12, CP3 Fri 16, Ship Sun 18, Review Feb 15].
    private func setup() throws -> (ModelContext, Project) {
        let ctx = try makeContext()
        let profile = Profile()
        profile.milestoneWeekdayMask = (1 << 1) | (1 << 5)
        profile.remindersEnabled = false
        ctx.insert(profile)
        let p = Project(name: "P", accentHex: 0x58CC02, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        return (ctx, p)
    }

    private func snapshot(plan: GitHubSnapshot.PlanFile?) -> GitHubSnapshot {
        GitHubSnapshot(description: "", readme: "", milestones: [], issues: [], lastCommit: nil, planFile: plan)
    }

    private func goal(_ id: String, due: Date) -> MetricsPayload.RemoteGoal {
        .init(id: id, title: "Goal \(id)", detail: nil, checkpoint: nil, due: due, done: nil, url: nil, metric: nil)
    }

    @Test func decodesCheckpointNamesFromPlanFile() throws {
        let json = """
        {"version":1,"checkpoints":[{"title":"Device testing","due":"2026-01-12"},{"title":"Polish","checkpoint":3}],
         "goals":[{"id":"a","title":"A","due":"2026-01-09"}]}
        """
        let plan = try MetricsPayload.decoder().decode(GitHubSnapshot.PlanFile.self, from: Data(json.utf8))
        #expect(plan.checkpoints?.map(\.title) == ["Device testing", "Polish"])
        #expect(plan.checkpoints?[1].checkpoint == 3)
    }

    @Test func planFileNamesCheckpointsButCustomNamesWin() throws {
        let (ctx, p) = try setup()
        let ms = p.sortedMilestones
        ScheduleEngine.rename(ms[2], to: "My own name")
        let plan = GitHubSnapshot.PlanFile(version: 1, checkpoints: [.init(title: "Device testing", due: day(2026, 1, 12)),
                                                                    .init(title: "Ignored", checkpoint: 3)],
                                           goals: [])
        GoalEngine.syncGitHub(snapshot(plan: plan), project: p, context: ctx)
        #expect(ms[1].title == "Device testing")
        #expect(ms[2].title == "My own name")
    }

    @Test func planFileAddsDatedCheckpointsAndPlacesGoalsOnThem() throws {
        let (ctx, p) = try setup()
        let before = p.sortedMilestones.count
        let plan = GitHubSnapshot.PlanFile(version: 1, checkpoints: [.init(title: "Widgets", due: day(2026, 1, 28))],
                                           goals: [goal("w", due: day(2026, 1, 28)), goal("x", due: day(2026, 1, 27))])
        GoalEngine.syncGitHub(snapshot(plan: plan), project: p, context: ctx)
        try ctx.save()
        #expect(p.sortedMilestones.count == before + 1)
        let added = try #require(p.sortedMilestones.first { $0.title == "Widgets" })
        #expect(added.dueDate == day(2026, 1, 28))
        #expect(Set(added.goals?.map(\.title) ?? []) == ["Goal w", "Goal x"])

        // Syncing again doesn't add it twice.
        GoalEngine.syncGitHub(snapshot(plan: plan), project: p, context: ctx)
        #expect(p.sortedMilestones.count == before + 1)
    }

    @Test func planFileReplacesSuggestionsEverywhere() throws {
        let (ctx, p) = try setup()
        let ms = p.sortedMilestones
        GoalEngine.addGoals(["Suggested"], source: .ai, to: ms[2], context: ctx)
        GoalEngine.addGoals(["Mine"], source: .manual, to: ms[2], context: ctx)
        let plan = GitHubSnapshot.PlanFile(version: 1, goals: [goal("a", due: day(2026, 1, 9))])
        GoalEngine.syncGitHub(snapshot(plan: plan), project: p, context: ctx)
        try ctx.save()
        #expect(ms[0].goals?.map(\.title) == ["Goal a"])
        #expect(ms[2].goals?.map(\.title) == ["Mine"]) // suggestion gone even though the file put nothing here
    }

    @Test func previewShowsRepoGoalsPerDeadline() {
        let dues = [day(2026, 1, 9), day(2026, 1, 12), day(2026, 1, 16)]
        let plan = GitHubSnapshot.PlanFile(version: 1, checkpoints: [.init(title: "Beta", due: day(2026, 1, 15))],
                                           goals: [goal("a", due: day(2026, 1, 10)), goal("b", due: day(2026, 3, 1))])
        let preview = GoalEngine.repoPreview(snapshot(plan: plan), dues: dues)
        #expect(preview.hasPlanFile)
        #expect(preview.goals[1].map(\.title) == ["Goal a"])
        #expect(preview.goals[2].map(\.title) == ["Goal b"]) // past the last deadline → last one
        #expect(preview.names == [nil, nil, "Beta"])
    }

    @Test func addMoveDeleteKeepAutomaticNamesInOrder() throws {
        let (ctx, p) = try setup()
        ScheduleEngine.addCheckpoint(to: p, title: "", due: day(2026, 1, 7), profile: nil, context: ctx)
        #expect(p.sortedMilestones.prefix(4).map(\.title) == ["Checkpoint 1", "Checkpoint 2", "Checkpoint 3", "Checkpoint 4"])

        let named = ScheduleEngine.addCheckpoint(to: p, title: "Pricing page", due: day(2026, 1, 14), profile: nil, context: ctx)
        #expect(named.titleIsCustom)

        let first = p.sortedMilestones[0]
        ScheduleEngine.reschedule(first, to: day(2026, 1, 13), profile: nil)
        #expect(p.sortedMilestones.map(\.title).prefix(5) == ["Checkpoint 1", "Checkpoint 2", "Checkpoint 3", "Pricing page", "Checkpoint 4"])

        ScheduleEngine.delete(p.sortedMilestones[0], context: ctx)
        try ctx.save()
        #expect(p.sortedMilestones.map(\.title).prefix(4) == ["Checkpoint 1", "Checkpoint 2", "Pricing page", "Checkpoint 3"])
        #expect(p.sortedMilestones.contains { $0.title == "Ship it" })
    }

    @Test func clearingANameGoesBackToAutomatic() throws {
        let (_, p) = try setup()
        let m = p.sortedMilestones[1]
        ScheduleEngine.rename(m, to: "Beta")
        #expect(m.title == "Beta" && m.titleIsCustom)
        ScheduleEngine.rename(m, to: "  ")
        #expect(m.title == "Checkpoint 2" && !m.titleIsCustom)
    }
}
