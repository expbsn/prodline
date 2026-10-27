#if DEBUG
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// -PRODLINE_STORE YES: the App Store screenshot set. Five projects with drawn logos, connected services,
/// goals from every source and six weeks of numbers, in an in-memory store (nothing reaches iCloud), with
/// syncing switched off so the screens hold still. Logos: design/make_demo_logos.swift.
enum StoreDemo {
    static let isOn = UserDefaults.standard.bool(forKey: "PRODLINE_STORE")

    private struct Spec {
        let slug: String, name: String, details: String, accent: Int
        let startedDaysAgo: Int, observeDays: Int
        let services: [IntegrationKind]
        var repo = ""
        let picked: [String]
        /// Today's numbers; the history grows toward them.
        let totals: [String: Double]
        var criteria: [(String, Double)] = []
        var verdict: Verdict? = nil
        var commitsPerDay = 0
        /// Day (from the start), title, goals (title, source, done hours ago or nil while open).
        let checkpoints: [(Int, String, [(String, GoalSource, Double?)])]
    }

    private static let specs: [Spec] = [
        Spec(slug: "tiny-invoice", name: "Tiny Invoice", details: "Invoices for freelancers, paid in one tap.", accent: 0x2F6BFF,
             startedDaysAgo: 25, observeDays: 28, services: [.stripe, .plausible], repo: "tinyinvoice/app",
             picked: ["revenue", "visits", "sales"], totals: ["revenue": 1240, "visits": 3180, "sales": 46],
             criteria: [("revenue", 2000), ("visits", 5000)], commitsPerDay: 4,
             checkpoints: [
                (3, "Invoice editor", [("Line items with tax", .github, 540), ("Export as PDF", .github, 530)]),
                (6, "Payments", [("Stripe checkout", .github, 470), ("Mark invoices paid by webhook", .github, 466)]),
                (10, "Landing page", [("Hero and pricing", .manual, 380), ("Reach 100 visitors", .metric, 360)]),
                (13, "Ship it", [("Post on Indie Hackers", .manual, 300), ("Submit to Product Hunt", .manual, 296)]),
                (20, "First customers", [("First sale", .metric, 150), ("Reply to every signup", .manual, 30)]),
                (29, "50 sales", [("Reach 50 sales", .metric, nil), ("Recurring invoices", .github, nil), ("Write a launch recap", .manual, nil)]),
             ]),
        Spec(slug: "pixel-quest", name: "Pixel Quest", details: "Daily five-minute pixel art puzzles.", accent: 0x8A45F5,
             startedDaysAgo: 39, observeDays: 28, services: [.appStore, .youtube, .tiktok],
             picked: ["downloads", "social_views", "followers"], totals: ["downloads": 2860, "social_views": 41200, "followers": 312, "videos_posted": 9],
             criteria: [("downloads", 2000), ("social_views", 25000)],
             checkpoints: [
                (4, "Puzzle engine", [("Daily puzzle generator", .repoFile, 900), ("Hint system", .repoFile, 880)]),
                (8, "Share results", [("Share card", .manual, 800)]),
                (13, "Ship it", [("Release on the App Store", .manual, 640)]),
                (20, "First clips", [("Post 5 TikToks", .manual, 450), ("Reach 10K views", .metric, 400)]),
             ]),
        Spec(slug: "habit-hero", name: "Habit Hero", details: "A habit tracker where streaks grow a plant.", accent: 0x46B500,
             startedDaysAgo: 8, observeDays: 28, services: [.appStore, .revenueCat], repo: "habithero/ios",
             picked: ["downloads", "active_trials", "revenue"], totals: ["downloads": 86, "active_trials": 14, "revenue": 38],
             commitsPerDay: 6,
             checkpoints: [
                (2, "Core loop", [("Habit list", .github, 150), ("Check in with one tap", .github, 146)]),
                (4, "Plant growth", [("Grow a leaf per streak day", .github, 100), ("Wilting after a miss", .manual, 98)]),
                (6, "Streak rewards", [("Reward animation", .ai, 52), ("Haptics on check-in", .manual, 50)]),
                (8, "Widgets", [("Small streak widget", .github, 3), ("Lock Screen widget", .github, nil),
                                ("Reach 100 downloads", .metric, nil), ("Record a demo clip", .manual, nil)]),
                (10, "Paywall", [("Yearly plan with trial", .github, nil), ("Restore purchases", .github, nil)]),
                (13, "Ship it", [("App Store screenshots", .manual, nil), ("Launch post", .manual, nil)]),
             ]),
        Spec(slug: "side-shop", name: "Side Shop", details: "A one-page shop for limited print runs.", accent: 0x2C2C2E,
             startedDaysAgo: 2, observeDays: 28, services: [.shopify, .plausible],
             picked: ["visits", "sales", "revenue"], totals: ["visits": 180, "sales": 0, "revenue": 0],
             checkpoints: [
                (2, "Product photos", [("Shoot the first print", .manual, 2), ("Product page copy", .manual, nil)]),
                (5, "Checkout", [("Shopify checkout", .manual, nil), ("Shipping rates", .manual, nil)]),
                (9, "Waitlist", [("Reach 300 visitors", .metric, nil)]),
                (13, "Ship it", [("Drop the first run", .manual, nil)]),
             ]),
        Spec(slug: "moonlog", name: "Moonlog", details: "A five-line journal that arrives by email every evening.", accent: 0x2B3170,
             startedDaysAgo: 60, observeDays: 70, services: [.kit, .bluesky],
             picked: ["new_subscribers", "followers"], totals: ["new_subscribers": 1920, "followers": 640],
             criteria: [("new_subscribers", 1000)], verdict: .keep,
             checkpoints: [
                (5, "Signup page", [("Double opt-in", .manual, 1300)]),
                (13, "Ship it", [("First evening email", .manual, 1130)]),
                (40, "1,000 subscribers", [("Reach 1,000 subscribers", .metric, 500)]),
                (64, "Paid tier", [("Pick a price", .manual, 20), ("Stripe for the paid tier", .manual, nil)]),
             ]),
    ]

    /// What the number goals count toward.
    private static let metricGoals: [String: (String, Double)] = [
        "Reach 100 visitors": ("visits", 100), "First sale": ("sales", 1), "Reach 50 sales": ("sales", 50),
        "Reach 10K views": ("social_views", 10_000), "Reach 100 downloads": ("downloads", 100),
        "Reach 300 visitors": ("visits", 300), "Reach 1,000 subscribers": ("new_subscribers", 1000),
    ]

    static func seed(_ context: ModelContext) {
        guard isOn, ((try? context.fetchCount(FetchDescriptor<Project>())) ?? 0) == 0 else { return }
        let profile = (try? context.fetch(FetchDescriptor<Profile>()))?.first ?? {
            let p = Profile(); context.insert(p); return p
        }()
        profile.onboarded = true
        profile.remindersEnabled = false
        profile.xp = 648
        profile.streak = 12
        profile.bestStreak = 15
        profile.streakActiveToday = Date.now.startOfDay
        profile.completedOnTime = 21
        profile.completedLate = 2
        // This week's wrap counts as watched, so its chip stays out of the shots.
        WeeklyReview.markWatched(WeeklyReview.reviewWeekStart())

        let now = Date.now
        let today = now.startOfDay
        for spec in specs {
            let p = Project(name: spec.name, accentHex: spec.accent, startDate: today.adding(days: -spec.startedDaysAgo),
                            buildDays: 14, observeDays: spec.observeDays)
            p.details = spec.details
            p.coverImage = cover(spec.slug)
            p.githubRepo = spec.repo
            p.integrations = spec.services.map { Integration(kind: $0) }
            p.pickedMetrics = spec.picked
            p.criteria = spec.criteria.map { SuccessCriterion(key: $0.0, target: $0.1) }
            if let v = spec.verdict {
                p.verdictRaw = v.rawValue
                p.verdictAt = p.buildEnd.adding(days: 28)
            }
            context.insert(p)

            for (day, title, goals) in spec.checkpoints {
                let m = Milestone(title: title, dueDate: p.startDate.adding(days: day), isLaunch: title == "Ship it")
                m.titleIsCustom = true
                context.insert(m)
                m.project = p
                for (i, g) in goals.enumerated() {
                    let goal = Goal(title: g.0, source: g.1, externalID: g.1 == .github ? "gh:\(10 + i)" : "", order: i)
                    if let (key, target) = metricGoals[g.0] {
                        goal.metricKey = key
                        goal.target = target
                    }
                    context.insert(goal)
                    goal.milestone = m
                    if let hours = g.2 { goal.setDone(true, at: now.addingTimeInterval(-hours * 3600)) }
                }
                if m.dueDate < today, goals.allSatisfy({ $0.2 != nil }) {
                    m.completedAt = (goals.compactMap(\.2).min().map { now.addingTimeInterval(-$0 * 3600) }) ?? m.dueDate
                    m.countedOnTime = true
                }
            }
            if spec.verdict == nil || p.phase() != .finished {
                let review = Milestone(title: "Traction review", dueDate: p.observeEnd.adding(days: -1))
                context.insert(review)
                review.project = p
            }

            history(for: p, spec: spec, now: now, context: context)
            if spec.commitsPerDay > 0 {
                var days: [String: Int] = [:]
                for d in 0...spec.startedDaysAgo {
                    let date = today.adding(days: -d)
                    days[date.formatted(.iso8601.year().month().day())] = max(0, spec.commitsPerDay + Int((sin(Double(d) * 1.7) * 3).rounded()))
                }
                p.commitDays = days
            }
        }
        try? context.save()
    }

    /// One reading a day since the start (two today), easing up toward today's totals with some wobble.
    private static func history(for p: Project, spec: Spec, now: Date, context: ModelContext) {
        let span = max(spec.startedDaysAgo, 1)
        for d in stride(from: span, through: 0, by: -1) {
            let t = Double(span - d) / Double(span)
            // Launched projects get their numbers after day 10 of the build; ones still building from day 2.
            let quiet = Double(spec.startedDaysAgo > 14 ? 9 : 1)
            let launched = max(0, (t * Double(span) - quiet) / max(Double(span) - quiet, 1))
            let f = pow(launched, 1.5) * (1 + 0.05 * sin(Double(d) * 1.9))
            var values: [String: Double] = [:]
            for (k, v) in spec.totals { values[k] = d == 0 ? v : (v * min(f, 1)).rounded() }
            let at = d == 0 ? now.addingTimeInterval(-90) : now.startOfDay.adding(days: -d).addingTimeInterval(20 * 3600)
            let s = MetricSnapshot(date: at, visits: values["visits"] ?? 0, socialViews: values["social_views"] ?? 0,
                                   revenue: values["revenue"] ?? 0,
                                   extras: values.filter { !["visits", "social_views", "revenue"].contains($0.key) })
            context.insert(s)
            s.project = p
        }
    }

    private static func cover(_ slug: String) -> Data? {
        #if canImport(UIKit)
        return UIImage(named: "Cover-\(slug)")?.jpegData(compressionQuality: 0.9)
        #else
        guard let tiff = NSImage(named: "Cover-\(slug)")?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        #endif
    }
}
#endif
