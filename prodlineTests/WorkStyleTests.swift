import Foundation
import Testing
@testable import prodline

@MainActor
@Suite("Work hours")
struct WorkStyleTests {
    @Test func styleSetsEveryTime() {
        let p = Profile()
        p.apply(.nightOwl, wrap: false)
        #expect(p.reminderHour == 21)
        #expect(p.nudgeHour == 23)
        #expect(WorkStyle.nightOwl.wrapHour == 21)
    }

    @Test func weekendWarriorsGetWeekendCheckpoints() {
        let p = Profile()
        p.apply(.weekendWarrior, wrap: false)
        #expect(p.hasWeekday(7) && p.hasWeekday(1))
        #expect(!p.hasWeekday(2))
        p.apply(.earlyBird, wrap: false)
        #expect(p.milestoneWeekdayMask == 34)
    }
}
