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

    @Test func xpStreakAndLevels() throws {
        let ctx = try makeContext()
        let profile = Profile()
        ctx.insert(profile)
        let today = day(2026, 3, 2)

        let a = Milestone(title: "A", dueDate: today)
        #expect(ScheduleEngine.complete(a, profile: profile, celebration: nil, now: today) == 10)
        #expect(profile.streak == 1)

        let launch = Milestone(title: "Ship", dueDate: today.adding(days: 3), isLaunch: true)
        #expect(ScheduleEngine.complete(launch, profile: profile, celebration: nil, now: today) == 50) // early counts as on time
        #expect(profile.streak == 2)

        let late = Milestone(title: "L", dueDate: today.adding(days: -1))
        #expect(ScheduleEngine.complete(late, profile: profile, celebration: nil, now: today) == 3)
        #expect(profile.streak == 2) // late doesn't extend or reset
        #expect(profile.xp == 63)
        #expect(profile.completedLate == 1)
        #expect(profile.onTimeRate == 2.0 / 3.0)

        // Completing twice gives nothing.
        #expect(ScheduleEngine.complete(a, profile: profile, celebration: nil, now: today) == 0)

        for i in 0..<4 { ScheduleEngine.complete(Milestone(title: "x\(i)", dueDate: today), profile: profile, celebration: nil, now: today) }
        #expect(profile.xp == 103)
        #expect(profile.level == 2)
        #expect(profile.bestStreak == 6)
    }

    @Test func missedDeadlineResetsStreakOnce() throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.streak = 5
        let p = Project(name: "P", accentHex: 0, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        ctx.insert(profile); ctx.insert(p)
        let m = Milestone(title: "M", dueDate: day(2026, 1, 9))
        ctx.insert(m); m.project = p

        #expect(ScheduleEngine.evaluateMissed(projects: [p], profile: profile, now: day(2026, 1, 9)) == 0) // due today: fine
        #expect(profile.streak == 5)
        #expect(ScheduleEngine.evaluateMissed(projects: [p], profile: profile, now: day(2026, 1, 10)) == 1)
        #expect(profile.streak == 0)
        profile.streak = 2
        #expect(ScheduleEngine.evaluateMissed(projects: [p], profile: profile, now: day(2026, 1, 11)) == 0) // already flagged
        #expect(profile.streak == 2)
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
        #expect(s.profile.streak == all.count)
        #expect(s.profile.xp == launches * ScheduleEngine.launchXP + others * ScheduleEngine.checkpointXP)
        #expect(s.profile.onTimeRate == 1)
    }

    @Test func oneSlipResetsTheStreakThenItRebuilds() throws {
        let start = day(2026, 1, 5)
        let s = try makeSeason(start: start, weeks: 4)
        let all = s.projects.flatMap { $0.milestones ?? [] }.sorted { $0.dueDate < $1.dueDate }
        let skipped = all[2]
        let end = all.last!.dueDate
        var d = start
        var streakBeforeSlip = 0
        while d <= end.adding(days: 1) {
            let missed = ScheduleEngine.evaluateMissed(projects: s.projects, profile: s.profile, now: d)
            if missed > 0 { #expect(s.profile.streak == 0) }
            for m in all where m.dueDate == d && m !== skipped {
                ScheduleEngine.complete(m, profile: s.profile, celebration: nil, now: d)
            }
            if d == skipped.dueDate { streakBeforeSlip = s.profile.streak }
            d = d.adding(days: 1)
        }
        #expect(skipped.missed)
        #expect(streakBeforeSlip >= 2)
        let doneAfterSlip = all.filter { $0.dueDate > skipped.dueDate && $0.isDone }.count
        #expect(s.profile.streak == doneAfterSlip)
        #expect(s.profile.bestStreak == max(streakBeforeSlip, doneAfterSlip))
    }

    @Test func faster7DayCadenceOverlapsMore() throws {
        let start = day(2026, 1, 5)
        let s = try makeSeason(start: start, weeks: 12, build: 10, observe: 21, every: 7)
        let maxOverlap = (0..<84).map { ScheduleEngine.overlap(on: start.adding(days: $0), projects: s.projects) }.max()
        #expect(maxOverlap == 5) // ceil(31 / 7)
    }
}
