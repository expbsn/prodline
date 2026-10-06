import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Deadline Live Activity")
struct LiveActivityTests {
    private func checkpoint(_ title: String, due: Date, goals: [(String, Bool)], in p: Project, ctx: ModelContext) -> Milestone {
        let m = Milestone(title: title, dueDate: due)
        ctx.insert(m)
        m.project = p
        for (i, (t, done)) in goals.enumerated() {
            let g = Goal(title: t, source: .manual, order: i)
            ctx.insert(g)
            g.milestone = m
            if done { g.setDone(true, at: due) }
        }
        return m
    }

    @Test func onlyTodaysCheckpointsWithOpenGoals() throws {
        let ctx = try makeContext()
        let today = day(2026, 10, 6)
        let p = Project(name: "Live", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let open = checkpoint("Open today", due: today, goals: [("A", true), ("B", false)], in: p, ctx: ctx)
        _ = checkpoint("All done today", due: today, goals: [("C", true)], in: p, ctx: ctx)
        _ = checkpoint("No goals today", due: today, goals: [], in: p, ctx: ctx)
        _ = checkpoint("Tomorrow", due: today.adding(days: 1), goals: [("D", false)], in: p, ctx: ctx)
        let finished = checkpoint("Finished today", due: today, goals: [("E", false)], in: p, ctx: ctx)
        finished.completedAt = today

        let found = LiveActivities.candidates([p], now: today.addingTimeInterval(9 * 3600))
        #expect(found.map(\.1.title) == [open.title])
    }

    @Test func stateListsOpenGoalsFirst() throws {
        let ctx = try makeContext()
        let today = day(2026, 10, 6)
        let p = Project(name: "Live", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let m = checkpoint("C", due: today, goals: [("Done one", true), ("Open one", false), ("Open two", false), ("Open three", false)],
                           in: p, ctx: ctx)
        let s = LiveActivities.state(m)
        #expect(s.goals.map(\.title) == ["Open one", "Open two", "Open three"])
        #expect(s.goalCount == 4 && s.goalsDone == 1 && s.openCount == 3 && !s.allDone)
    }
}

@MainActor
@Suite("Widget ticks", .serialized)
struct WidgetTickTests {
    @Test func queuedTicksApplyOnlyToHandGoals() throws {
        let ctx = try makeContext()
        let p = Project(name: "Ticks", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let m = Milestone(title: "C", dueDate: day(2026, 10, 8))
        ctx.insert(m); m.project = p
        let manual = Goal(title: "Manual", source: .manual)
        let synced = Goal(title: "From file", source: .repoFile)
        for g in [manual, synced] { ctx.insert(g); g.milestone = m }

        _ = WidgetTicks.take()
        WidgetTicks.record(goalID: manual.id.uuidString, done: true)
        WidgetTicks.record(goalID: synced.id.uuidString, done: true)
        #expect(WidgetTicks.pending().count == 2)

        #expect(WidgetPublisher.applyWidgetTicks(projects: [p], profile: nil))
        #expect(manual.isDone)
        #expect(!synced.isDone)
        #expect(WidgetTicks.pending().isEmpty)
        #expect(!WidgetPublisher.applyWidgetTicks(projects: [p], profile: nil))
    }
}

@MainActor
@Suite("Goal order")
struct GoalOrderTests {
    @Test func openGoalsComeFirstEverywhere() throws {
        let ctx = try makeContext()
        let p = Project(name: "Order", accentHex: 0x58CC02, startDate: day(2026, 10, 1), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        let m = Milestone(title: "C", dueDate: day(2026, 10, 8))
        ctx.insert(m); m.project = p
        // Six goals, the first five done: the widget used to get only those five.
        for i in 0..<6 {
            let g = Goal(title: "G\(i)", source: .manual, order: i)
            ctx.insert(g); g.milestone = m
            if i < 5 { g.setDone(true, at: day(2026, 10, 2)) }
        }
        #expect(m.displayGoals.map(\.title) == ["G5", "G0", "G1", "G2", "G3", "G4"])
        let widget = WidgetPublisher.make(p, refresher: DataRefresher(), now: day(2026, 10, 3))
        #expect(widget.checkpoints.first?.goals.first?.title == "G5")
        #expect(widget.checkpoints.first?.goalsDone == 5)
        #expect(widget.checkpoints.first?.goalCount == 6)
    }
}
