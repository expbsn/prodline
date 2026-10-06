import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Weekly review", .serialized)
struct WeeklyReviewTests {
    private func at(_ d: Date, _ hour: Int) -> Date { d.addingTimeInterval(TimeInterval(hour * 3600)) }

    @Test func coversThisWeekFromSundayEvening() {
        // Mon Oct 5 – Sun Oct 11, 2026.
        let monday = day(2026, 10, 5)
        #expect(WeeklyReview.reviewWeekStart(now: at(day(2026, 10, 11), 17)) == day(2026, 9, 28))
        #expect(WeeklyReview.reviewWeekStart(now: at(day(2026, 10, 11), 18)) == monday)
        #expect(WeeklyReview.reviewWeekStart(now: at(day(2026, 10, 13), 9)) == monday)
    }

    @Test func waitsUntilWatched() {
        let defaults = UserDefaults(suiteName: "review-test")!
        defaults.removePersistentDomain(forName: "review-test")
        let sundayNight = at(day(2026, 10, 11), 19)
        #expect(!WeeklyReview.isWaiting(now: at(day(2026, 10, 11), 12), defaults: defaults))
        #expect(WeeklyReview.isWaiting(now: sundayNight, defaults: defaults))
        WeeklyReview.markWatched(WeeklyReview.reviewWeekStart(now: sundayNight), defaults: defaults)
        #expect(!WeeklyReview.isWaiting(now: sundayNight, defaults: defaults))
        // Gone after three days even if never watched.
        defaults.removePersistentDomain(forName: "review-test")
        #expect(!WeeklyReview.isWaiting(now: at(day(2026, 10, 15), 9), defaults: defaults))
    }

    @Test func statsCountTheWeek() throws {
        let ctx = try makeContext()
        let profile = Profile()
        ctx.insert(profile)
        let p = Project(name: "Week", accentHex: 0x58CC02, startDate: day(2026, 9, 20), buildDays: 28, observeDays: 28)
        ctx.insert(p)
        let m = Milestone(title: "C", dueDate: day(2026, 10, 7))
        ctx.insert(m); m.project = p
        m.completedAt = at(day(2026, 10, 7), 10)
        m.xpEarned = 10
        for (i, d) in [day(2026, 10, 5), day(2026, 10, 7), day(2026, 9, 30)].enumerated() {
            let g = Goal(title: "G\(i)", source: .manual)
            ctx.insert(g); g.milestone = m
            g.setDone(true, at: at(d, 9))
            g.xpPaid = 3
        }
        p.commitDays = [Momentum.key(day(2026, 10, 8)): 5, Momentum.key(day(2026, 10, 9)): 2, Momentum.key(day(2026, 10, 1)): 9]

        let s = WeeklyReview.make(projects: [p], profile: profile, weekStart: day(2026, 10, 5), now: at(day(2026, 10, 11), 19))
        #expect(s.week == 41)
        #expect(s.goalsDone == 2)
        #expect(s.xp == 10 + 6)
        #expect(s.checkpointsOnTime == 1)
        #expect(s.commits == [0, 0, 0, 5, 2, 0, 0])
        #expect(s.busiestDay == 3)
        #expect(s.active == [true, false, true, true, true, false, false])
        #expect(s.projectOfWeek?.project.name == "Week")
        #expect(ReviewCopy(stats: s).activeDays.contains("4"))
    }
}
