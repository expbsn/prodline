import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Keep, pivot or kill")
struct VerdictTests {
    private func result(_ target: Double, _ actual: Double) -> VerdictEngine.Result {
        VerdictEngine.Result(criterion: SuccessCriterion(key: "visits", target: target), actual: actual)
    }

    @Test func suggestionFollowsTheTargets() {
        #expect(VerdictEngine.suggestion([]) == nil)
        #expect(VerdictEngine.suggestion([result(100, 120), result(50, 50)]) == .keep)
        #expect(VerdictEngine.suggestion([result(100, 120), result(50, 5)]) == .pivot)
        #expect(VerdictEngine.suggestion([result(100, 45)]) == .pivot)
        #expect(VerdictEngine.suggestion([result(100, 10), result(50, 2)]) == .kill)
    }

    @Test func dueOnceTheObservePhaseEndsAndKeepAsksAgainLater() throws {
        let ctx = try makeContext()
        let profile = Profile()
        ctx.insert(profile)
        let p = Project(name: "Verdict", accentHex: 0x58CC02, startDate: day(2026, 9, 1), buildDays: 14, observeDays: 14)
        ctx.insert(p)
        // Observe ends Sep 29.
        #expect(!VerdictEngine.isDue(p, now: day(2026, 9, 20)))
        #expect(VerdictEngine.canDecide(p, now: day(2026, 9, 20)))
        #expect(VerdictEngine.isDue(p, now: day(2026, 10, 2)))

        VerdictEngine.keep(p, days: 28, profile: profile, now: day(2026, 10, 2))
        #expect(profile.xp == VerdictEngine.xp)
        #expect(p.observeEnd == day(2026, 10, 30))
        #expect(!VerdictEngine.isDue(p, now: day(2026, 10, 10)))
        #expect(VerdictEngine.isDue(p, now: day(2026, 10, 31)))
    }

    @Test func pivotStartsAFreshBuildAndKillCloses() throws {
        let ctx = try makeContext()
        let profile = Profile()
        ctx.insert(profile)
        let p = Project(name: "Old", accentHex: 0xA35CFF, startDate: day(2026, 8, 1), buildDays: 14, observeDays: 14)
        p.githubRepo = "me/old"
        p.criteria = [SuccessCriterion(key: "revenue", target: 100)]
        ctx.insert(p)
        let next = VerdictEngine.pivot(p, newName: "Old 2", note: "Smaller scope", profile: profile, context: ctx, now: day(2026, 10, 6))
        #expect(p.verdict == .pivot)
        #expect(!VerdictEngine.isDue(p, now: day(2026, 10, 7)))
        #expect(next.startDate == day(2026, 10, 6))
        #expect(next.githubRepo == "me/old")
        #expect(next.criteria.map(\.key) == ["revenue"])
        #expect(next.details == "Smaller scope")
        #expect(!(next.milestones ?? []).isEmpty)

        let q = Project(name: "Dead", accentHex: 0xFF4B4B, startDate: day(2026, 8, 1), buildDays: 14, observeDays: 14)
        ctx.insert(q)
        VerdictEngine.kill(q, lesson: "Nobody searched for it", profile: profile, now: day(2026, 10, 6))
        #expect(q.verdict == .kill && q.verdictNote == "Nobody searched for it")
        #expect(profile.xp == 2 * VerdictEngine.xp)
        VerdictEngine.reopen(q, profile: profile)
        #expect(q.verdict == nil && profile.xp == VerdictEngine.xp)
        #expect(VerdictEngine.isDue(q, now: day(2026, 10, 7)))
    }
}
