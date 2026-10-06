import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Schedule engine")
struct ScheduleTests {
    let monFri = (1 << 1) | (1 << 5)

    @Test func milestonesForTwoWeekBuild() throws {
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28) // Monday
        let ms = ScheduleEngine.makeMilestones(for: p, weekdayMask: monFri)
        #expect(ms.map(\.title) == ["Checkpoint 1", "Checkpoint 2", "Checkpoint 3", "Ship it", "Traction review"])
        #expect(ms.map(\.dueDate) == [day(2026, 1, 9), day(2026, 1, 12), day(2026, 1, 16), day(2026, 1, 18), day(2026, 2, 15)])
        #expect(ms.filter(\.isLaunch).count == 1)
        // Every checkpoint is inside the build phase and on a chosen weekday.
        for m in ms where !m.isLaunch && m.title != "Traction review" {
            #expect(m.dueDate > p.startDate && m.dueDate < p.launchDay)
            let wd = Calendar.current.component(.weekday, from: m.dueDate)
            #expect(wd == 2 || wd == 6)
        }
    }

    @Test func noWeekdaysMeansOnlyLaunchAndReview() {
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        #expect(ScheduleEngine.makeMilestones(for: p, weekdayMask: 0).count == 2)
    }

    @Test func shortBuildDoesNotCrash() {
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 3, observeDays: 7)
        let ms = ScheduleEngine.makeMilestones(for: p, weekdayMask: 0b1111111)
        #expect(ms.count == 3) // one checkpoint (day 1), launch (day 2), review
    }

    @Test func phases() {
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        #expect(p.phase(on: day(2026, 1, 4)) == .upcoming)
        #expect(p.phase(on: day(2026, 1, 5)) == .building)
        #expect(p.phase(on: day(2026, 1, 18)) == .building)
        #expect(p.phase(on: day(2026, 1, 19)) == .observing)
        #expect(p.phase(on: day(2026, 2, 15)) == .observing)
        #expect(p.phase(on: day(2026, 2, 16)) == .finished)
    }

    @Test func xpAndLevels() throws {
        let ctx = try makeContext()
        let profile = Profile()
        ctx.insert(profile)
        let today = day(2026, 3, 2)

        let a = Milestone(title: "A", dueDate: today)
        #expect(ScheduleEngine.complete(a, profile: profile, celebration: nil, now: today) == 10)

        let launch = Milestone(title: "Ship", dueDate: today.adding(days: 3), isLaunch: true)
        #expect(ScheduleEngine.complete(launch, profile: profile, celebration: nil, now: today) == 50) // early counts as on time

        let late = Milestone(title: "L", dueDate: today.adding(days: -1))
        #expect(ScheduleEngine.complete(late, profile: profile, celebration: nil, now: today) == 3)
        #expect(profile.xp == 63)
        #expect(profile.completedLate == 1)
        #expect(profile.onTimeRate == 2.0 / 3.0)

        // Completing twice gives nothing.
        #expect(ScheduleEngine.complete(a, profile: profile, celebration: nil, now: today) == 0)

        for i in 0..<4 { ScheduleEngine.complete(Milestone(title: "x\(i)", dueDate: today), profile: profile, celebration: nil, now: today) }
        #expect(profile.xp == 103)
        #expect(profile.level == 2)
    }

    @Test func missedDeadlineIsFlaggedOnce() throws {
        let ctx = try makeContext()
        let profile = Profile()
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        ctx.insert(profile); ctx.insert(p)
        let m = Milestone(title: "M", dueDate: day(2026, 1, 9))
        ctx.insert(m); m.project = p

        #expect(ScheduleEngine.evaluateMissed(projects: [p], profile: profile, now: day(2026, 1, 9)) == 0) // due today: fine
        #expect(ScheduleEngine.evaluateMissed(projects: [p], profile: profile, now: day(2026, 1, 10)) == 1)
        #expect(m.missed)
        #expect(ScheduleEngine.evaluateMissed(projects: [p], profile: profile, now: day(2026, 1, 11)) == 0) // already flagged
    }

    @Test func streakCountsDaysWithProgress() throws {
        let ctx = try makeContext()
        let profile = Profile()
        ctx.insert(profile)
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let m = Milestone(title: "M", dueDate: day(2026, 1, 12))
        ctx.insert(m); m.project = p
        GoalEngine.addGoals(["a", "b", "c"], source: .manual, to: m, context: ctx)
        let goals = m.sortedGoals
        goals[0].setDone(true, at: day(2026, 1, 6).addingTimeInterval(3600 * 10))
        goals[1].setDone(true, at: day(2026, 1, 7).addingTimeInterval(3600 * 22))
        p.commitDays = [Momentum.key(day(2026, 1, 8)): 2]          // a commit counts too
        goals[2].setDone(true, at: day(2026, 1, 10).addingTimeInterval(3600))   // after a gap on the 9th

        // Several things on one day still count once; a missed day breaks the run.
        Streak.update(profile, projects: [p], now: day(2026, 1, 10).addingTimeInterval(3600 * 12))
        #expect(profile.streak == 1)
        #expect(profile.bestStreak == 3)
        // The next day the streak is still alive until something happens (or the day ends).
        Streak.update(profile, projects: [p], now: day(2026, 1, 11).addingTimeInterval(3600 * 9))
        #expect(profile.streak == 1)
        #expect(!Streak.isActiveToday(profile, now: day(2026, 1, 11).addingTimeInterval(3600 * 9)))
        // A whole day without progress ends it.
        Streak.update(profile, projects: [p], now: day(2026, 1, 12).addingTimeInterval(3600 * 9))
        #expect(profile.streak == 0)
        #expect(profile.bestStreak == 3)
    }

    @Test func nextProjectFollowsCadence() throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.newProjectEveryDays = 14
        ctx.insert(profile)
        #expect(ScheduleEngine.nextProjectDate(projects: [], profile: profile) == Date.now.startOfDay)
        let a = Project(name: "A", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        let b = Project(name: "B", accentHex: 0, startDate: day(2026, 1, 19), buildDays: 14, observeDays: 28)
        #expect(ScheduleEngine.nextProjectDate(projects: [a, b], profile: profile) == day(2026, 2, 2))
    }
}

/// Replays a full season of the default scheme day by day.
@MainActor
@Suite("Backtest: 12-week season")
struct BacktestTests {
    struct Season {
        let ctx: ModelContext
        let profile: Profile
        var projects: [Project] = []
    }

    /// New project every `every` days from `start`, the way a disciplined user would create them.
    func makeSeason(start: Date, weeks: Int, build: Int = 14, observe: Int = 28, every: Int = 14) throws -> Season {
        let ctx = try makeContext()
        let profile = Profile()
        profile.buildDays = build; profile.observeDays = observe; profile.newProjectEveryDays = every
        profile.milestoneWeekdayMask = (1 << 1) | (1 << 5)
        profile.remindersEnabled = false
        ctx.insert(profile)
        var s = Season(ctx: ctx, profile: profile)
        var date = start
        var i = 0
        while date < start.adding(days: weeks * 7) {
            let p = Project(name: "P\(i)", accentHex: Theme.swatches[i % Theme.swatches.count], startDate: date,
                            buildDays: build, observeDays: observe)
            ScheduleEngine.createProject(p, profile: profile, context: ctx)
            s.projects.append(p)
            date = ScheduleEngine.nextProjectDate(projects: s.projects, profile: profile)
            i += 1
        }
        return s
    }

    @Test func overlapMatchesTheSchemeMath() throws {
        let start = day(2026, 1, 5)
        let s = try makeSeason(start: start, weeks: 12)
        #expect(s.projects.count == 6)
        let counts = (0..<84).map { ScheduleEngine.overlap(on: start.adding(days: $0), projects: s.projects) }
        #expect(counts.max() == 3) // ceil((14 + 28) / 14)
        #expect(counts.first == 1)
        // Never more than one project in its build phase at a time with a 14/14 cadence.
        for d in 0..<84 {
            let building = s.projects.filter { $0.phase(on: start.adding(days: d)) == .building }.count
            #expect(building == 1)
        }
    }

    @Test func perfectSeasonEarnsExpectedXP() throws {
        let start = day(2026, 1, 5)
        let s = try makeSeason(start: start, weeks: 12)
        let all = s.projects.flatMap { $0.milestones ?? [] }
        let end = all.map(\.dueDate).max()!
        var d = start
        while d <= end {
            ScheduleEngine.evaluateMissed(projects: s.projects, profile: s.profile, now: d)
            for m in all where m.dueDate == d { ScheduleEngine.complete(m, profile: s.profile, celebration: nil, now: d) }
            d = d.adding(days: 1)
        }
        let launches = all.filter(\.isLaunch).count
        let others = all.count - launches
        #expect(all.allSatisfy { $0.isDone })
        #expect(all.allSatisfy { !$0.missed })
        #expect(s.profile.xp == launches * ScheduleEngine.launchXP + others * ScheduleEngine.checkpointXP)
        #expect(s.profile.onTimeRate == 1)
    }

    @Test func oneSlipIsFlaggedAndTheRestStaysOnTime() throws {
        let start = day(2026, 1, 5)
        let s = try makeSeason(start: start, weeks: 4)
        let all = s.projects.flatMap { $0.milestones ?? [] }.sorted { $0.dueDate < $1.dueDate }
        let skipped = all[2]
        let end = all.last!.dueDate
        var d = start
        while d <= end.adding(days: 1) {
            ScheduleEngine.evaluateMissed(projects: s.projects, profile: s.profile, now: d)
            for m in all where m.dueDate == d && m !== skipped {
                ScheduleEngine.complete(m, profile: s.profile, celebration: nil, now: d)
            }
            d = d.adding(days: 1)
        }
        #expect(skipped.missed && !skipped.isDone)
        #expect(all.filter { $0 !== skipped }.allSatisfy { $0.isDone && !$0.missed })
        #expect(s.profile.completedOnTime == all.count - 1)
    }

    @Test func faster7DayCadenceOverlapsMore() throws {
        let start = day(2026, 1, 5)
        let s = try makeSeason(start: start, weeks: 12, build: 10, observe: 21, every: 7)
        let maxOverlap = (0..<84).map { ScheduleEngine.overlap(on: start.adding(days: $0), projects: s.projects) }.max()
        #expect(maxOverlap == 5) // ceil(31 / 7)
    }
}

@MainActor
@Suite("Away and late")
struct AwayAndLateTests {
    @Test func collectedXPBecomesOneSummary() {
        let c = CelebrationCenter()
        c.beginCollecting()
        c.fire(title: "+10 XP", subtitle: "Nailed it", xp: 10, kind: .checkpoint)
        c.fire(title: "+9 XP", subtitle: "3 goals", xp: 9, kind: .goals(3))
        #expect(c.banner == nil) // held while collecting
        c.endCollecting(awayTitle: true)
        #expect(c.banner?.title == "+19 XP while you were away")
        #expect(c.banner?.subtitle == "1 checkpoint · 3 goals done")
    }

    @Test func singleCollectedEventShowsAsIs() {
        let c = CelebrationCenter()
        c.beginCollecting()
        c.fire(title: "+3 XP", subtitle: "Ship pricing page", xp: 3, kind: .goals(1))
        c.endCollecting(awayTitle: true)
        #expect(c.banner?.title == "+3 XP")
    }

    @Test func lateReminderNamesTheLateCheckpoint() throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.milestoneWeekdayMask = (1 << 1) | (1 << 5)
        profile.remindersEnabled = false
        ctx.insert(profile)
        let p = Project(name: "Late Co", accentHex: 0x58CC02, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        let first = p.sortedMilestones[0] // Fri Jan 9
        GoalEngine.addGoals(["Pricing page", "Onboarding"], source: .manual, to: first, context: ctx)
        let r = try #require(ScheduleEngine.lateReminder(projects: [p], now: day(2026, 1, 11)))
        #expect(r.title == "\(first.title) is 2 days late")
        #expect(r.subtitle.hasPrefix("Late Co · 2 goals still open"))
        first.completedAt = day(2026, 1, 11)
        #expect(ScheduleEngine.lateReminder(projects: [p], now: day(2026, 1, 11)) == nil)
    }
}
