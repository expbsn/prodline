import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Widgets")
struct WidgetTests {
    @Test func dueTextReadsNaturally() {
        let today = day(2026, 1, 12)
        func cp(_ d: Int) -> WidgetCheckpoint {
            WidgetCheckpoint(title: "C", due: today.adding(days: d), done: false, isLaunch: false, goals: [], goalCount: 0, goalsDone: 0)
        }
        #expect(cp(0).dueText(from: today) == "Today")
        #expect(cp(1).dueText(from: today) == "Tomorrow")
        #expect(cp(4).dueText(from: today) == "In 4 days")
        #expect(cp(-1).dueText(from: today) == "1 day late")
        #expect(cp(-3).dueText(from: today) == "3 days late")
    }

    @Test func mostUrgentFollowsTheNextOpenDeadline() {
        let data = WidgetData.sample(on: day(2026, 1, 12))
        // Side Shop's checkpoint is tomorrow; Habit Hero's in 2 days; Pixel Quest's in 18.
        #expect(data.mostUrgent(on: day(2026, 1, 12))?.name == "Side Shop")
        #expect(data.project(id: "sample-pixel")?.name == "Pixel Quest")
        #expect(data.project(id: nil) == nil)
    }

    @Test func phaseAndDayFollowTheClock() {
        let p = WidgetData.sample(on: day(2026, 1, 12)).projects[0] // Habit Hero: started 9 days ago, 14-day build
        #expect(p.phase(on: day(2026, 1, 12)) == .building)
        #expect(p.phaseDay(on: day(2026, 1, 12)).day == 10)
        #expect(p.phase(on: day(2026, 1, 20)) == .observing)
        #expect(p.phase(on: day(2026, 3, 1)) == .finished)
    }

    @Test func publisherMapsCheckpointsGoalsAndHistory() throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.milestoneWeekdayMask = (1 << 1) | (1 << 5)
        profile.remindersEnabled = false
        ctx.insert(profile)
        let now = day(2026, 1, 12).addingTimeInterval(12 * 3600)
        let p = Project(name: "Widgeted", accentHex: 0xA35CFF, startDate: day(2026, 1, 5), buildDays: 14, observeDays: 28)
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        let first = p.sortedMilestones[0]
        first.completedAt = first.dueDate
        GoalEngine.addGoals(["One", "Two"], source: .manual, to: p.sortedMilestones[1], context: ctx)
        p.sortedMilestones[1].sortedGoals[0].setDone(true)
        for d in 0..<5 {
            let s = MetricSnapshot(date: day(2026, 1, 7 + d).addingTimeInterval(20 * 3600),
                                   visits: Double(100 * (d + 1)), socialViews: 0, revenue: 0)
            ctx.insert(s); s.project = p
        }
        try ctx.save()

        let refresher = DataRefresher()
        let w = WidgetPublisher.make(p, refresher: refresher, now: now)
        #expect(w.name == "Widgeted" && w.accentHex == 0xA35CFF)
        #expect(w.checkpoints.count == p.sortedMilestones.count)
        #expect(w.checkpoints[0].done)
        let next = try #require(w.next(on: now))
        #expect(next.title == p.sortedMilestones[1].title)
        #expect(next.goalCount == 2 && next.goalsDone == 1)

        let visits = try #require(w.metric("visits"))
        #expect(visits.value == 500)
        #expect(visits.spark.last == 500)
        #expect(visits.spark.count >= 2)
        #expect(visits.delta?.hasPrefix("+") == true)
    }
}
