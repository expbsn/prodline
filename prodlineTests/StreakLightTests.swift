import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Streak flame")
struct StreakLightTests {
    @Test func lightsOnceWhenTodayFirstCounts() throws {
        let ctx = try makeContext()
        let profile = Profile(); ctx.insert(profile)
        let p = Project(name: "Lit", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let m = Milestone(title: "C", dueDate: day(2026, 10, 9)); ctx.insert(m); m.project = p
        let a = Goal(title: "A", source: .manual), b = Goal(title: "B", source: .manual)
        for g in [a, b] { ctx.insert(g); g.milestone = m }
        let center = CelebrationCenter()
        let now = day(2026, 10, 6).addingTimeInterval(10 * 3600)

        a.setDone(true, at: day(2026, 10, 5).addingTimeInterval(3600))   // yesterday
        Streak.refresh(profile, projects: [p], celebration: center, now: now)
        #expect(center.streakLit == nil)

        b.setDone(true, at: now)                                          // today's first
        Streak.refresh(profile, projects: [p], celebration: center, now: now)
        #expect(center.streakLit?.days == 2)

        center.endStreak()
        Streak.refresh(profile, projects: [p], celebration: center, now: now.addingTimeInterval(60))
        #expect(center.streakLit == nil)
    }
}
