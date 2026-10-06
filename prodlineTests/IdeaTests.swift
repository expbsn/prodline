import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Build limit")
struct BuildLimitTests {
    @Test func buildingAndUpcomingProjectsTakeSlots() throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.buildLimit = 2
        let now = day(2026, 10, 6)
        let building = Project(name: "A", accentHex: 1, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        let upcoming = Project(name: "B", accentHex: 1, startDate: day(2026, 10, 20), buildDays: 14, observeDays: 28)
        let observing = Project(name: "C", accentHex: 1, startDate: day(2026, 9, 1), buildDays: 14, observeDays: 60)
        for p in [building, upcoming, observing] { ctx.insert(p) }
        let all = [building, upcoming, observing]

        #expect(ProjectLimit.building(all, now: now).map(\.name) == ["A", "B"])
        #expect(ProjectLimit.isFull(all, profile: profile, now: now))
        #expect(ProjectLimit.nextFree(all, now: now) == day(2026, 10, 15))

        profile.buildLimit = 3
        #expect(!ProjectLimit.isFull(all, profile: profile, now: now))
        #expect(ProjectLimit.freeSlots(all, profile: profile, now: now) == 1)
        profile.buildLimit = 0
        #expect(!ProjectLimit.isFull(all, profile: profile, now: now))
        #expect(ProjectLimit.freeSlots(all, profile: profile, now: now) == nil)

        // A killed project gives its slot back.
        profile.buildLimit = 2
        building.verdictRaw = Verdict.kill.rawValue
        #expect(!ProjectLimit.isFull(all, profile: profile, now: now))
    }
}
