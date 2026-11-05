import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Stages")
struct StageTests {
    /// Starts Oct 1: Build (14 days, Oct 1–14), then Observe (28 days, ends with the call).
    private func project(_ ctx: ModelContext, profile: Profile) -> Project {
        let p = Project(name: "Shipper", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        p.stages = Stage.defaults(buildDays: 14, observeDays: 28)
        for m in ScheduleEngine.makeMilestones(for: p, weekdayMask: 0) { ctx.insert(m); m.project = p }
        return p
    }

    @Test func projectsFromBeforeStagesBecomeBuildAndObserve() throws {
        let ctx = try makeContext()
        let p = Project(name: "Old", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        #expect(p.stagesData == nil)
        #expect(p.stages(on: day(2026, 10, 6)).map(\.name) == ["Build", "Observe"])
        #expect(p.phase(on: day(2026, 10, 6)) == .building)
        #expect(p.phase(on: day(2026, 10, 20)) == .observing)
        StageEngine.migrate(p, now: day(2026, 10, 20))
        #expect(p.stagesData != nil)
        #expect(p.stages.first?.finishedAt == day(2026, 10, 15))
        #expect(p.stages.last?.decides == true)
    }

    @Test func movingOnNeedsEveryCheckpointInTheStageDone() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = project(ctx, profile: profile)
        let now = day(2026, 10, 10).addingTimeInterval(9 * 3600)
        #expect(!StageEngine.canFinishStage(p, now: now))
        #expect(StageEngine.finishStage(p, profile: profile, now: now) == nil)
        let ship = p.sortedMilestones.first { $0.isLaunch }!
        ScheduleEngine.complete(ship, profile: profile, celebration: nil, now: now)
        #expect(StageEngine.canFinishStage(p, now: now))
    }

    @Test func finishingEarlyStartsTheNextStageTodayAndMovesItsCheckpoints() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = project(ctx, profile: profile)
        let now = day(2026, 10, 10).addingTimeInterval(9 * 3600)
        StageEngine.assignStages(p)
        ScheduleEngine.complete(p.sortedMilestones.first { $0.isLaunch }!, profile: profile, celebration: nil, now: now)
        let xpBefore = profile.xp

        let r = try #require(StageEngine.finishStage(p, profile: profile, now: now))
        #expect(r.daysEarly == 4)
        #expect(r.shipped)
        #expect(r.next?.name == "Observe")
        #expect(profile.xp - xpBefore == 4 * ScheduleEngine.earlyXPPerDay)
        let spans = p.spans(on: now)
        #expect(spans[0].state == .done)
        #expect(spans[1].state == .current)
        #expect(spans[1].start == day(2026, 10, 10))
        // The traction review sits on Observe's last day, now 4 days sooner.
        let review = p.sortedMilestones.last!
        #expect(review.title == "Traction review")
        #expect(review.dueDate == day(2026, 11, 6))
        #expect(p.phase(on: now) == .observing)
    }

    @Test func aStageThatRunsOverPushesTheRestBack() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = project(ctx, profile: profile)
        StageEngine.migrate(p)
        StageEngine.assignStages(p)
        let now = day(2026, 10, 17)   // Build was due Oct 14
        let span = try #require(p.currentSpan(on: now))
        #expect(span.stage.name == "Build")
        #expect(span.daysOver(on: now) == 3)
        #expect(p.phase(on: now) == .building)
        StageEngine.realign(p, profile: nil, now: now)
        // Observe now starts tomorrow at the earliest, so its review moves 3 days back.
        #expect(p.sortedMilestones.last?.dueDate == day(2026, 11, 14))
    }

    @Test func draftsKeepTheirPlanUntilStarted() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = Project(name: "Later", accentHex: 0x58CC02, startDate: .now, buildDays: 14, observeDays: 28)
        p.isDraft = true
        p.stages = [Stage(name: "Research", days: 7), Stage(name: "Build", days: 14), Stage(name: "Observe", days: 28, decides: true)]
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        #expect((p.milestones ?? []).isEmpty)
        #expect(!p.plannedCheckpoints.isEmpty)
        #expect(p.phase() == .upcoming)
        #expect(ProjectLimit.building([p]).isEmpty)

        StageEngine.start(p, on: day(2026, 12, 1), profile: profile, context: ctx)
        #expect(!p.isDraft)
        #expect(p.plannedCheckpoints.isEmpty)
        let ms = p.sortedMilestones
        #expect(ms.first { $0.isLaunch }?.dueDate == day(2026, 12, 21))   // last day of Build
        #expect(ms.last?.title == "Traction review")
        #expect(ms.last?.dueDate == day(2027, 1, 18))
        #expect(ms.contains { $0.title == "Research done" && $0.dueDate == day(2026, 12, 7) })
    }

    @Test func aDecisionMidPlanKeepsMovingOnAndKillClosesEverything() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = Project(name: "Beta", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        p.stages = [Stage(name: "Beta", days: 7, decides: true), Stage(name: "Launch", days: 7), Stage(name: "Observe", days: 14, decides: true)]
        let now = day(2026, 10, 8)
        #expect(VerdictEngine.isDue(p, now: now))
        VerdictEngine.keep(p, days: 14, profile: profile, now: now)
        #expect(p.currentSpan(on: now)?.stage.name == "Launch")
        VerdictEngine.reopen(p, profile: profile)
        #expect(p.currentSpan(on: now)?.stage.name == "Beta")
        VerdictEngine.kill(p, lesson: "", profile: profile, now: now)
        #expect(p.isFinished)
        #expect(p.currentSpan(on: now) == nil)
    }

    @Test func theLaunchSitsBeforeTheFirstDecision() {
        let stages = [Stage(name: "Research", days: 5), Stage(name: "Build", days: 10), Stage(name: "Launch week", days: 7),
                      Stage(name: "Observe", days: 28, decides: true)]
        let plan = StageEngine.defaultCheckpoints(stages: stages, start: day(2026, 10, 1), weekdayMask: 0)
        #expect(plan.filter(\.isLaunch).map(\.stageID) == [stages[2].id])
        #expect(plan.map(\.title) == ["Research done", "Build done", "Ship it", "Traction review"])
    }
}
