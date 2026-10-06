import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Let's ship")
struct ShipTests {
    private func project(_ ctx: ModelContext, profile: Profile) -> Project {
        // Starts Oct 1, 14-day build: launch day Oct 14, observe until Nov 11.
        let p = Project(name: "Shipper", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let cp = Milestone(title: "Checkpoint 1", dueDate: day(2026, 10, 11))
        let empty = Milestone(title: "Checkpoint 2", dueDate: day(2026, 10, 12))
        let launch = Milestone(title: "Ship it", dueDate: day(2026, 10, 14), isLaunch: true)
        let review = Milestone(title: "Traction review", dueDate: day(2026, 11, 10))
        for m in [cp, empty, launch, review] { ctx.insert(m); m.project = p }
        let g = Goal(title: "Build it", source: .manual)
        ctx.insert(g); g.milestone = cp
        return p
    }

    @Test func onlyWhileBuildingWithEveryGoalDone() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = project(ctx, profile: profile)
        let now = day(2026, 10, 6)
        #expect(!ScheduleEngine.canShip(p, now: now))
        p.sortedMilestones[0].goals?.first?.setDone(true, at: now)
        #expect(ScheduleEngine.canShip(p, now: now))
        #expect(!ScheduleEngine.canShip(p, now: day(2026, 10, 20)))
    }

    @Test func shippingEarlyMovesTheLaunchAndKeepsTheObservePhase() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = project(ctx, profile: profile)
        let now = day(2026, 10, 10).addingTimeInterval(9 * 3600)
        p.sortedMilestones[0].goals?.first?.setDone(true, at: now)

        let r = ScheduleEngine.ship(p, profile: profile, now: now)
        #expect(r.daysEarly == 4)
        #expect(p.launchDay == day(2026, 10, 10))
        #expect(p.phase(on: day(2026, 10, 11)) == .observing)
        #expect(p.observeDays == 28)
        let ms = p.sortedMilestones
        let shipDay = day(2026, 10, 10)
        let buildDone = ms.filter { $0.dueDate <= shipDay }.allSatisfy { $0.isDone }
        #expect(buildDone)
        let launchDue = ms.first { $0.isLaunch }?.dueDate
        #expect(launchDue == shipDay)
        let review = ms.last
        #expect(review?.title == "Traction review")
        #expect(review?.dueDate == day(2026, 11, 6))
        #expect(review?.isDone == false)
        // Early bonus + launch + the open build checkpoints, all on time.
        #expect(r.xp == 4 * ScheduleEngine.earlyXPPerDay + ScheduleEngine.launchXP + 2 * ScheduleEngine.checkpointXP)
        #expect(profile.xp == r.xp)
    }

    @Test func shippingOnLaunchDayIsNotEarly() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = project(ctx, profile: profile)
        let r = ScheduleEngine.ship(p, profile: profile, now: day(2026, 10, 14).addingTimeInterval(3600))
        #expect(r.daysEarly == 0)
        #expect(p.buildDays == 14)
    }
}
