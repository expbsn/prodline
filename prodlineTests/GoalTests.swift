import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Goals")
struct GoalTests {
    /// Monday Jan 5 2026, 14-day build, Mon+Fri checkpoints → [CP1 Fri 9, CP2 Mon 12, CP3 Fri 16, Ship Sun 18, Review Feb 15].
    private func setup(start: Date = day(2026, 1, 5)) throws -> (ModelContext, Project, Profile) {
        let ctx = try makeContext()
        let profile = Profile()
        profile.milestoneWeekdayMask = (1 << 1) | (1 << 5)
        profile.remindersEnabled = false
        ctx.insert(profile)
        let p = Project(name: "P", accentHex: 0x58CC02, startDate: start, buildDays: 14, observeDays: 28)
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        return (ctx, p, profile)
    }

    private func goal(_ id: String, checkpoint: Int? = nil, due: Date? = nil, done: Bool? = nil,
                      metric: MetricsPayload.RemoteGoal.Target? = nil) -> MetricsPayload.RemoteGoal {
        .init(id: id, title: "Goal \(id)", detail: nil, checkpoint: checkpoint, due: due, done: done, url: nil, metric: metric)
    }

    @Test func decodesGoalsFromPayload() throws {
        let json = """
        {"asOf":"2026-10-04T12:00:00Z","metrics":[],
         "goals":[{"id":"a","title":"Ship it","checkpoint":2,"done":true},
                  {"id":"b","title":"500 signups","due":"2026-10-09T00:00:00Z","metric":{"key":"signups","target":500}}]}
        """
        let p = try MetricsPayload.decoder().decode(MetricsPayload.self, from: Data(json.utf8))
        #expect(p.goals?.count == 2)
        #expect(p.goals?[0].checkpoint == 2 && p.goals?[0].done == true)
        #expect(p.goals?[1].metric == .init(key: "signups", target: 500))
    }

    @Test func placement() throws {
        let (_, p, _) = try setup()
        let ms = p.sortedMilestones
        #expect(GoalEngine.milestone(checkpoint: 2, due: nil, in: p) === ms[1])
        #expect(GoalEngine.milestone(checkpoint: 99, due: day(2026, 1, 13), in: p) === ms[2]) // first on/after Jan 13 → Fri 16
        #expect(GoalEngine.milestone(checkpoint: nil, due: day(2027, 1, 1), in: p) === ms.last)
        ms[0].completedAt = .now
        #expect(GoalEngine.milestone(checkpoint: nil, due: nil, in: p) === ms[1]) // next open
    }

    @Test func apiSyncUpsertsMovesAndRemoves() throws {
        let (ctx, p, _) = try setup()
        let ms = p.sortedMilestones
        GoalEngine.syncAPI([goal("a", checkpoint: 1), goal("b", checkpoint: 2)], project: p, context: ctx)
        #expect(ms[0].goals?.map(\.title) == ["Goal a"])
        #expect(ms[1].goals?.count == 1)

        // b moves to checkpoint 3 and is done; a disappears upstream; c is new.
        GoalEngine.syncAPI([goal("b", checkpoint: 3, done: true), goal("c", checkpoint: 1)], project: p, context: ctx)
        try ctx.save()
        #expect(ms[0].goals?.map(\.externalID) == ["api:c"])
        #expect(ms[1].goals?.isEmpty == true)
        #expect(ms[2].goals?.first?.externalID == "api:b")
        #expect(ms[2].goals?.first?.isDone == true)
    }

    @Test func doneGoalsSurviveRemovalUpstream() throws {
        let (ctx, p, _) = try setup()
        GoalEngine.syncAPI([goal("a", checkpoint: 1, done: true)], project: p, context: ctx)
        GoalEngine.syncAPI([], project: p, context: ctx)
        try ctx.save()
        #expect(p.sortedMilestones[0].goals?.count == 1)
    }

    @Test func remoteGoalsReplaceSuggestions() throws {
        let (ctx, p, _) = try setup()
        let ms = p.sortedMilestones
        GoalEngine.addGoals(["Suggested A", "Suggested B"], source: .ai, to: ms[0], context: ctx)
        GoalEngine.addGoals(["Suggested C"], source: .ai, to: ms[1], context: ctx)
        GoalEngine.addGoals(["Mine"], source: .manual, to: ms[0], context: ctx)
        GoalEngine.syncAPI([goal("x", checkpoint: 1)], project: p, context: ctx)
        try ctx.save()
        #expect(Set(ms[0].goals?.map(\.title) ?? []) == ["Goal x", "Mine"]) // AI replaced, manual kept
        #expect(ms[1].goals?.map(\.title) == ["Suggested C"]) // untouched checkpoint keeps its suggestion
    }

    @Test func autoCompleteWhenAllGoalsDone() throws {
        let (ctx, p, profile) = try setup()
        let ms = p.sortedMilestones
        GoalEngine.addGoals(["One", "Two"], source: .manual, to: ms[0], context: ctx)
        let now = day(2026, 1, 8)
        #expect(GoalEngine.autoComplete(projects: [p], profile: profile, celebration: nil, now: now).isEmpty)
        ms[0].sortedGoals[0].setDone(true)
        #expect(GoalEngine.autoComplete(projects: [p], profile: profile, celebration: nil, now: now).isEmpty)
        ms[0].sortedGoals[1].setDone(true)
        let done = GoalEngine.autoComplete(projects: [p], profile: profile, celebration: nil, now: now)
        #expect(done.count == 1 && done[0] === ms[0])
        #expect(ms[0].isDone && ms[0].completedOnTime)
        #expect(profile.xp == ScheduleEngine.checkpointXP && profile.streak == 1)
        // Plain checkpoints (no goals) are never auto-completed.
        #expect(!ms[1].isDone)
    }

    @Test func metricGoalsCompleteFromLiveData() async throws {
        let (ctx, p, profile) = try setup(start: Date.now.adding(days: -3))
        let ms = p.sortedMilestones
        GoalEngine.syncAPI([goal("s", checkpoint: 1, metric: .init(key: "signups", target: 50))], project: p, context: ctx)
        let r = DataRefresher { _ in (FakeClient { _ in payload(asOf: .now, visits: 10, extras: ["signups": 60]) }, false) }
        await r.refresh(projects: [p], context: ctx, force: true)
        GoalEngine.afterRefresh(projects: [p], profile: profile, refresher: r, celebration: nil, context: ctx)
        #expect(ms[0].goals?.first?.isDone == true)
        #expect(ms[0].isDone) // only goal done → checkpoint completed
    }

    @Test func remoteDoneFlagCompletesCheckpoint() async throws {
        let (ctx, p, profile) = try setup(start: Date.now.adding(days: -3))
        let ms = p.sortedMilestones
        let client = FakeClient { n in
            payload(asOf: .now, visits: 1,
                    goals: [.init(id: "a", title: "Goal a", detail: nil, checkpoint: 1, due: nil, done: n > 1, url: nil, metric: nil)])
        }
        let r = DataRefresher { _ in (client, false) }
        await r.refresh(projects: [p], context: ctx, force: true)
        GoalEngine.afterRefresh(projects: [p], profile: profile, refresher: r, celebration: nil, context: ctx)
        #expect(!ms[0].isDone)
        await r.refresh(projects: [p], context: ctx, force: true)
        GoalEngine.afterRefresh(projects: [p], profile: profile, refresher: r, celebration: nil, context: ctx)
        #expect(ms[0].isDone)
    }

    @Test func tractionTargetsDuringObserve() async throws {
        let (ctx, p, profile) = try setup(start: Date.now.adding(days: -20)) // observing
        let r = DataRefresher { _ in (FakeClient { _ in payload(asOf: .now, visits: 1234, revenue: 80) }, false) }
        await r.refresh(projects: [p], context: ctx, force: true)
        GoalEngine.afterRefresh(projects: [p], profile: profile, refresher: r, celebration: nil, context: ctx)
        let review = try #require(p.sortedMilestones.last)
        let metricGoals = (review.goals ?? []).filter { $0.source == .metric }
        #expect(metricGoals.count == 2)
        #expect(metricGoals.allSatisfy { ($0.target ?? 0) > 1234 || $0.metricKey == "revenue" })
        // Created once only.
        GoalEngine.afterRefresh(projects: [p], profile: profile, refresher: r, celebration: nil, context: ctx)
        #expect((review.goals ?? []).filter { $0.source == .metric }.count == 2)
    }

    @Test func targets() {
        #expect(GoalEngine.niceTarget(1234) == 1300)
        #expect(GoalEngine.niceTarget(87) == 90)
        #expect(GoalEngine.niceTarget(3) == 10)
        #expect(GoalEngine.niceTarget(48_200) == 50_000)
        #expect(GoalEngine.stretchTarget(current: 1000, dailyRate: 100, daysLeft: 10) == 2300) // 2000 × 1.15
        #expect(GoalEngine.stretchTarget(current: 1000, dailyRate: 0, daysLeft: 10) == 1200)   // at least +20%
    }

    @Test func repoParsing() {
        #expect(GitHubRepoRef("apple/swift")?.slug == "apple/swift")
        #expect(GitHubRepoRef("https://github.com/expbsn/prodline.git")?.slug == "expbsn/prodline")
        #expect(GitHubRepoRef("github.com/a-b/c.d/tree/main")?.slug == "a-b/c.d")
        #expect(GitHubRepoRef("not a repo") == nil)
        #expect(GitHubRepoRef("") == nil)
    }

    @Test func githubIssuesBecomeGoals() throws {
        let (ctx, p, _) = try setup()
        let ms = p.sortedMilestones
        typealias I = GitHubSnapshot.Issue
        let snap = GitHubSnapshot(
            description: "", readme: "",
            milestones: [.init(number: 7, title: "MVP", state: "open", due_on: nil),
                         .init(number: 9, title: "Launch", state: "open", due_on: day(2026, 1, 17))],
            issues: [I(number: 1, title: "Grid", state: "closed", html_url: "u1", labels: [], milestone: .init(number: 7), pull_request: nil),
                     I(number: 2, title: "Checkout", state: "open", html_url: "u2", labels: [], milestone: .init(number: 9), pull_request: nil),
                     I(number: 3, title: "Emails", state: "open", html_url: "u3", labels: [.init(name: "Prodline")], milestone: nil, pull_request: nil),
                     I(number: 4, title: "Unplanned", state: "open", html_url: "u4", labels: [], milestone: nil, pull_request: nil)],
            lastCommit: nil)
        GoalEngine.syncGitHub(snap, project: p, context: ctx)
        try ctx.save()
        #expect(Set(ms[0].goals?.map(\.title) ?? []) == ["Grid", "Emails"]) // 1st milestone → CP1; label → next open
        #expect(ms[3].goals?.map(\.title) == ["Checkout"])                   // due Jan 17 → Ship (Jan 18)
        #expect(ms[0].goals?.first { $0.title == "Grid" }?.isDone == true)
        #expect(!(p.sortedMilestones.flatMap { $0.goals ?? [] }.contains { $0.title == "Unplanned" }))
    }

    @Test func planFileBecomesGoals() throws {
        let (ctx, p, _) = try setup()
        let ms = p.sortedMilestones
        let json = #"""
        {"version": 1, "goals": [
          {"id": "auth", "title": "Sign in with Apple", "checkpoint": 1, "done": true},
          {"id": "post", "title": "Launch post drafted", "due": "2026-01-17"}
        ]}
        """#
        let plan = try MetricsPayload.decoder().decode(GitHubSnapshot.PlanFile.self, from: Data(json.utf8))
        #expect(plan.goals[1].due == day(2026, 1, 17)) // date-only, local calendar
        GoalEngine.addGoals(["Suggested"], source: .ai, to: ms[0], context: ctx)
        var snap = GitHubSnapshot(description: "", readme: "", milestones: [], issues: [], lastCommit: nil, planFile: plan)
        GoalEngine.syncGitHub(snap, project: p, context: ctx)
        try ctx.save()
        #expect(ms[0].goals?.map(\.title) == ["Sign in with Apple"]) // file replaces the suggestion
        #expect(ms[0].goals?.first?.isDone == true && ms[0].goals?.first?.source == .repoFile)
        #expect(ms[3].goals?.map(\.title) == ["Launch post drafted"]) // Jan 17 → Ship it (Jan 18)

        // A broken file keeps what we have…
        snap.planFile = nil
        snap.planFileError = "prodline.json isn't valid"
        GoalEngine.syncGitHub(snap, project: p, context: ctx)
        try ctx.save()
        #expect(ms[3].goals?.count == 1)
        // …a deleted file clears open goals but keeps done ones.
        snap.planFileError = nil
        GoalEngine.syncGitHub(snap, project: p, context: ctx)
        try ctx.save()
        #expect(ms[3].goals?.isEmpty == true)
        #expect(ms[0].goals?.count == 1)
    }

    @Test func aiPromptCarriesProjectContext() {
        let gh = GitHubSnapshot(description: "Poster shop", readme: "# Side Shop\nStripe checkout", milestones: [],
                                issues: [.init(number: 1, title: "Cart drawer", state: "open", html_url: "", labels: [], milestone: nil, pull_request: nil)],
                                lastCommit: nil)
        let prompt = GoalPlanner.prompt(name: "Side Shop", details: "Limited prints", buildDays: 14,
                                        deadlines: [.init(title: "Checkpoint 1", date: day(2026, 1, 9)),
                                                    .init(title: "Ship it", date: day(2026, 1, 18))],
                                        github: gh)
        for s in ["Side Shop", "Limited prints", "1. Checkpoint 1", "2. Ship it", "Poster shop", "Cart drawer", "Stripe checkout"] {
            #expect(prompt.contains(s), "missing \(s)")
        }
    }

    /// Runs where Apple Intelligence can actually generate. The simulator reports the model as available
    /// but fails generation (ModelManager error 1026); the app surfaces that as "couldn't suggest goals".
    @Test(.enabled(if: GoalPlanner.isAvailable)) func onDeviceModelDraftsGoals() async throws {
        let plan: [Int: [String]]
        do {
            plan = try await GoalPlanner.draft(
            name: "Habit Hero", details: "A habit tracker that grows a plant with your streak.", buildDays: 14,
            deadlines: [.init(title: "Checkpoint 1", date: day(2026, 1, 9)), .init(title: "Checkpoint 2", date: day(2026, 1, 12)),
                        .init(title: "Ship it", date: day(2026, 1, 18)), .init(title: "Traction review", date: day(2026, 2, 15))],
            github: nil)
        } catch {
            print("On-device model can't generate here: \(error)")
            return
        }
        #expect(!plan.isEmpty)
        #expect(plan[4] == nil) // never for the review
        #expect(plan.values.allSatisfy { (1...3).contains($0.count) })
    }
}

@MainActor
@Suite("Goals × mock server (integration)", .enabled(if: MockServer.base != nil), .serialized)
struct GoalIntegrationTests {
    @Test func mockGitHubSnapshot() async throws {
        let client = GitHubClient(repo: GitHubRepoRef("demo/side-shop")!, token: nil, base: URL(string: MockServer.base! + "/github")!)
        let snap = try await client.fetch()
        #expect(snap.description.contains("print runs"))
        #expect(snap.readme.contains("Stripe"))
        #expect(snap.milestones.count == 2)
        #expect(!snap.issues.contains { $0.number == 14 }) // pull requests are filtered out
        #expect(snap.lastCommit != nil)
        #expect(snap.planFile?.goals.map(\.id) == ["shipping-rates", "launch-post"])
        #expect(snap.planFileError == nil)
        await #expect(throws: GitHubError.notFound) {
            _ = try await GitHubClient(repo: GitHubRepoRef("demo/nope")!, base: URL(string: MockServer.base! + "/github")!).fetch()
        }
    }

    @Test func apiGoalsFlowIntoCheckpoints() async throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.remindersEnabled = false
        ctx.insert(profile)
        DemoData.load(baseURL: MockServer.base!, profile: profile, context: ctx)
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        defer { for p in projects { Keychain.delete(p.id.uuidString) } }
        let hh = try #require(projects.first { $0.name == "Habit Hero" })
        let r = DataRefresher()
        await r.refresh(projects: [hh], context: ctx, force: true)
        GoalEngine.afterRefresh(projects: [hh], profile: profile, refresher: r, celebration: nil, context: ctx)
        let goals = hh.sortedMilestones.flatMap { $0.goals ?? [] }.filter { $0.source == .api }
        #expect(Set(goals.map(\.externalID)) == ["api:onboarding", "api:streak-share", "api:signups-500"])
        #expect(hh.sortedMilestones[2].goals?.count == 2) // checkpoint 3

        // Upstream marks the last open goal done → the checkpoint completes itself.
        try await MockServer.post("habit-hero", key: "hh_live_demo", body: #"{"type":"goal","id":"onboarding","done":true}"#)
        await r.refresh(projects: [hh], context: ctx, force: true)
        GoalEngine.afterRefresh(projects: [hh], profile: profile, refresher: r, celebration: nil, context: ctx)
        #expect(hh.sortedMilestones[2].isDone)
        try await MockServer.post("habit-hero", key: "hh_live_demo", body: #"{"type":"goal","id":"onboarding","done":false}"#)
    }

    @Test func githubIssuesCloseCheckpoint() async throws {
        UserDefaults.standard.set(MockServer.base! + "/github", forKey: "githubAPIBase")
        let ctx = try makeContext()
        let profile = Profile()
        profile.remindersEnabled = false
        ctx.insert(profile)
        let p = Project(name: "Side Shop", accentHex: 0xFF9600, startDate: Date.now.adding(days: -2), buildDays: 14, observeDays: 28)
        p.githubRepo = "demo/side-shop"
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        let gh = GitHubService()
        await gh.refresh(projects: [p], force: true)
        GoalEngine.syncGitHub(try #require(gh.snapshots[p.id]), project: p, context: ctx)
        let first = p.sortedMilestones[0]
        #expect(Set(first.goals?.map(\.title) ?? []) == ["Product grid", "Cart drawer", "Order confirmation email"])
        #expect(p.sortedMilestones[2].goals?.map(\.title) == ["Add shipping rates table"]) // from prodline.json
        #expect(p.sortedMilestones[2].goals?.first?.source == .repoFile)
        #expect(p.lastCommitAt != nil)

        for n in [12, 15] {
            try await MockServer.post("side-shop", key: "ss_live_demo", body: #"{"type":"close_issue","number":\#(n)}"#)
        }
        await gh.refresh(projects: [p], force: true)
        GoalEngine.syncGitHub(try #require(gh.snapshots[p.id]), project: p, context: ctx)
        GoalEngine.autoComplete(projects: [p], profile: profile, celebration: nil)
        #expect(first.isDone)
        for n in [12, 15] {
            try await MockServer.post("side-shop", key: "ss_live_demo", body: #"{"type":"reopen_issue","number":\#(n)}"#)
        }
    }
}

/// Backtest against the real GitHub API: this repo's own prodline.json.
/// Run with  TEST_RUNNER_PRODLINE_REAL_GITHUB=expbsn/prodline xcodebuild test …
@MainActor
@Suite("Real GitHub backtest", .enabled(if: ProcessInfo.processInfo.environment["PRODLINE_REAL_GITHUB"] != nil))
struct RealGitHubBacktest {
    @Test func ownRepoPlanMapsOntoCheckpoints() async throws {
        let slug = try #require(ProcessInfo.processInfo.environment["PRODLINE_REAL_GITHUB"])
        let snap = try await GitHubClient(repo: try #require(GitHubRepoRef(slug))).fetch()
        #expect(snap.planFileError == nil)
        let plan = try #require(snap.planFile)
        #expect(plan.goals.count >= 5)
        #expect(Set(plan.goals.map(\.id)).count == plan.goals.count) // stable, unique ids
        #expect(!snap.readme.isEmpty || !snap.description.isEmpty || snap.lastCommit != nil)

        // Prodline as a project: Sun Oct 4 2026, 14-day build, Mon+Fri checkpoints
        // → CP1 Mon 5, CP2 Fri 9, CP3 Mon 12, CP4 Fri 16, Ship it Sat 17, review.
        let ctx = try makeContext()
        let profile = Profile()
        profile.milestoneWeekdayMask = (1 << 1) | (1 << 5)
        profile.remindersEnabled = false
        ctx.insert(profile)
        let p = Project(name: "Prodline", accentHex: 0x1CB0F6, startDate: day(2026, 10, 4), buildDays: 14, observeDays: 28)
        p.githubRepo = slug
        ScheduleEngine.createProject(p, profile: profile, context: ctx)
        GoalEngine.syncGitHub(snap, project: p, context: ctx)
        try ctx.save()

        let ms = p.sortedMilestones
        let fileGoals = ms.flatMap { $0.goals ?? [] }.filter { $0.source == .repoFile }
        #expect(fileGoals.count == plan.goals.count)
        // Every goal lands on the first deadline on/after its due date.
        for g in plan.goals {
            guard let due = g.due else { continue }
            let expected = ms.first { $0.dueDate >= due.startOfDay } ?? ms.last!
            #expect(expected.goals?.contains { $0.externalID == "file:\(g.id)" } == true, "\(g.id) misplaced")
        }
        // Checkpoint 1 is fully done in the file → completes itself.
        let done = GoalEngine.autoComplete(projects: [p], profile: profile, celebration: nil, now: day(2026, 10, 5))
        #expect(done.contains { $0 === ms[0] })
        #expect(!ms[1].isDone) // still has open goals
    }
}
