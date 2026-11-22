import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("prodline.json stages")
struct PlanStagesTests {
    private let today = Date.now.startOfDay

    private func setup(start: Date) throws -> (ModelContext, Project) {
        let ctx = try makeContext()
        let profile = Profile()
        profile.remindersEnabled = false
        ctx.insert(profile)
        let p = Project(name: "P", accentHex: 0x58CC02, startDate: start, buildDays: 14, observeDays: 28)
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        return (ctx, p)
    }

    private func decode(_ json: String) throws -> GitHubSnapshot.PlanFile {
        try MetricsPayload.decoder().decode(GitHubSnapshot.PlanFile.self, from: Data(json.utf8))
    }

    private let file = """
    {"version":1,
     "stages":[{"id":"build","name":"Build","days":10},{"id":"beta","name":"Beta","days":7},
               {"name":"Observe","days":14,"decides":true}],
     "checkpoints":[{"stage":"build","day":5,"title":"Core loop"},{"stage":"build","title":"Build done"},
                    {"stage":"beta","day":2,"title":"TestFlight out"},{"stage":"observe","title":"Traction review"}],
     "goals":[{"id":"a","title":"Paywall","stage":"beta","day":1},{"id":"b","title":"Loop","stage":"build","day":3}]}
    """

    @Test func decodesStagesAndStageReferences() throws {
        let plan = try decode(file)
        #expect(plan.stages?.map(\.name) == ["Build", "Beta", "Observe"])
        #expect(plan.stages?[2].decides == true)
        #expect(plan.checkpoints?[2].stage == "beta")
        #expect(plan.goals[0].stage == "beta")
    }

    @Test func fileStagesReplaceTheProjectsAndPlaceCheckpointsByStage() throws {
        let (ctx, p) = try setup(start: today)
        GoalEngine.applyPlan(try decode(file), project: p, context: ctx)

        #expect(p.stagesFromFile)
        #expect(p.stages.map(\.name) == ["Build", "Beta", "Observe"])
        #expect(p.stages.map(\.days) == [10, 7, 14])
        #expect(p.stages.map(\.decides) == [false, false, true])

        let ms = p.sortedMilestones
        #expect(ms.map(\.title) == ["Core loop", "Build done", "TestFlight out", "Traction review"])
        // Day 5 of Build, Build's last day, day 2 of Beta, Observe's last day.
        #expect(ms.map(\.dueDate) == [today.adding(days: 4), today.adding(days: 9), today.adding(days: 11), today.adding(days: 30)])
        let ids = p.stages.map { $0.id.uuidString }
        #expect(ms.map(\.stageID) == [ids[0], ids[0], ids[1], ids[2]])
        // Goals by stage land on that stage's checkpoints.
        #expect(ms[0].goals?.map(\.title) == ["Loop"])
        #expect(ms[2].goals?.map(\.title) == ["Paywall"])
    }

    @Test func stageIDsStayPutAcrossSyncs() throws {
        let (ctx, p) = try setup(start: today)
        let plan = try decode(file)
        GoalEngine.applyPlan(plan, project: p, context: ctx)
        let first = p.stages.map(\.id)
        GoalEngine.applyPlan(plan, project: p, context: ctx)
        #expect(p.stages.map(\.id) == first)
        #expect(first[0] == PlanStages.id(seed: p.id, key: "build"))
        #expect(p.sortedMilestones.count == 4)
    }

    @Test func checkpointsFollowAStageThatRunsOver() throws {
        // Started 12 days ago: Build (10 days) is two days over, so Beta starts tomorrow.
        let (ctx, p) = try setup(start: today.adding(days: -12))
        GoalEngine.applyPlan(try decode(file), project: p, context: ctx)
        let beta = p.sortedMilestones.first { $0.title == "TestFlight out" }
        #expect(beta?.dueDate == today.adding(days: 2))
        #expect(p.currentStage?.name == "Build")
    }

    @Test func finishedStagesCarryOverByName() throws {
        // A project from before stages: Build finished in the app, ids not derived from the file.
        let (ctx, p) = try setup(start: today.adding(days: -20))
        var stages = p.stages
        stages[0].finishedAt = today.adding(days: -6)
        p.stages = stages
        GoalEngine.applyPlan(try decode(file), project: p, context: ctx)
        #expect(p.stages.map(\.name) == ["Build", "Beta", "Observe"])
        #expect(p.stages[0].finishedAt == today.adding(days: -6))
        #expect(p.currentStage?.name == "Beta")
    }

    @Test func finishedStagesTheFileDropsStayInFront() throws {
        let (ctx, p) = try setup(start: today.adding(days: -20))
        var stages = p.stages
        stages[0].name = "Research"
        stages[0].finishedAt = today.adding(days: -10)
        p.stages = stages
        GoalEngine.applyPlan(try decode(file), project: p, context: ctx)
        #expect(p.stages.map(\.name) == ["Research", "Build", "Beta", "Observe"])
        #expect(p.currentStage?.name == "Build")
    }

    @Test func aFileWithoutStagesLeavesTheProjectsOwn() throws {
        let (ctx, p) = try setup(start: today)
        let before = p.stages
        let plan = try decode("""
        {"version":1,"checkpoints":[{"day":3,"title":"Three"}],"goals":[{"id":"a","title":"A","day":3}]}
        """)
        GoalEngine.applyPlan(plan, project: p, context: ctx)
        #expect(!p.stagesFromFile)
        #expect(p.stages == before)
        #expect(p.sortedMilestones.map(\.dueDate) == [today.adding(days: 2)])
    }

    @Test func removingTheFileHandsTheStagesBack() throws {
        let (ctx, p) = try setup(start: today)
        GoalEngine.syncGitHub(GitHubSnapshot(description: "", readme: "", milestones: [], issues: [], lastCommit: nil,
                                             planFile: try decode(file)), project: p, context: ctx)
        #expect(p.stagesFromFile)
        GoalEngine.syncGitHub(GitHubSnapshot(description: "", readme: "", milestones: [], issues: [], lastCommit: nil,
                                             planFile: nil), project: p, context: ctx)
        #expect(!p.stagesFromFile)
        #expect(!p.followsPlanFile)
        #expect(p.stages.map(\.name) == ["Build", "Beta", "Observe"])
    }

    @Test func theReposOwnPlanFilePlacesEveryCheckpointAndGoal() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("prodline.json")
        let plan = try MetricsPayload.decoder().decode(GitHubSnapshot.PlanFile.self, from: Data(contentsOf: url))
        let keys = Set((plan.stages ?? []).map(PlanStages.key))
        #expect(!keys.isEmpty)
        for c in plan.checkpoints ?? [] { #expect(c.stage.map { keys.contains(PlanStages.key($0)) } ?? true, "\(c.title)") }
        for g in plan.goals { #expect(g.stage.map { keys.contains(PlanStages.key($0)) } ?? true, "\(g.id)") }

        let (ctx, p) = try setup(start: today)
        GoalEngine.applyPlan(plan, project: p, context: ctx)
        #expect(p.sortedMilestones.count == plan.checkpoints?.count)
        let placed = p.sortedMilestones.flatMap { $0.goals ?? [] }.count
        #expect(placed == plan.goals.count)
    }

    @Test func previewPlansTheFilesCheckpointsBeforeTheProjectExists() throws {
        let plan = try decode(file)
        let seed = UUID()
        let stages = PlanStages.merge(plan.stages ?? [], seed: seed, current: [])
        let planned = PlanStages.plannedCheckpoints(plan, stages: stages, start: today, seed: seed)
        #expect(planned.map(\.title) == ["Core loop", "Build done", "TestFlight out", "Traction review"])
        #expect(planned.map(\.day) == [4, 9, 1, 13])
        #expect(planned.map(\.stageID) == [stages[0].id, stages[0].id, stages[1].id, stages[2].id])

        let preview = GoalEngine.repoPreview(GitHubSnapshot(description: "", readme: "", milestones: [], issues: [],
                                                            lastCommit: nil, planFile: plan),
                                             dues: planned.map { StageEngine.date(of: $0, stages: stages, start: today) },
                                             start: today, stages: stages, seed: seed)
        #expect(preview.goals[0].map(\.title) == ["Loop"])
        #expect(preview.goals[2].map(\.title) == ["Paywall"])
    }
}
