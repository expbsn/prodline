#if DEBUG
import SwiftUI
import SwiftData
import AppKit

/// -PRODLINE_DEMO YES on an empty store (e.g. an unsigned build without iCloud): the demo projects,
/// with their bundled covers and some numbers, so the layout can be looked at.
enum MacDemo {
    static func seedIfNeeded(_ context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "PRODLINE_DEMO"),
              ((try? context.fetchCount(FetchDescriptor<Project>())) ?? 0) == 0 else { return }
        let profile = (try? context.fetch(FetchDescriptor<Profile>()))?.first ?? {
            let p = Profile(); context.insert(p); return p
        }()
        profile.onboarded = true
        profile.remindersEnabled = false
        profile.streak = 6
        let specs: [(String, String, String, Int, Int, (Double, Double, Double), [String: Double])] = [
            ("habit-hero", "Habit Hero", "A tiny habit tracker that rewards streaks with plant growth.", 9, 0x58CC02, (1240, 3100, 0), ["downloads": 86]),
            ("pixel-quest", "Pixel Quest", "Daily five-minute pixel art puzzles.", 23, 0xA35CFF, (5320, 41200, 482.5), ["followers": 312, "videos_posted": 7]),
            ("side-shop", "Side Shop", "A one-page shop for limited print runs.", 2, 0x3A3A3C, (180, 0, 0), [:]),
        ]
        for (slug, name, details, ago, accent, nums, extras) in specs {
            let p = Project(name: name, accentHex: accent, startDate: Date.now.startOfDay.adding(days: -ago),
                            buildDays: profile.buildDays, observeDays: profile.observeDays)
            p.details = details
            if let img = NSImage(named: "Cover-\(slug)"), let tiff = img.tiffRepresentation,
               let jpg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                p.coverImage = jpg
            }
            context.insert(p)
            for (i, m) in ScheduleEngine.makeMilestones(for: p, weekdayMask: profile.milestoneWeekdayMask).enumerated() {
                context.insert(m)
                m.project = p
                if m.dueDate < Date.now.startOfDay { m.completedAt = m.dueDate }
                for (n, title) in ["Ship the onboarding", "Add the share card", "Post a launch clip"].enumerated() where i < 4 {
                    let g = Goal(title: title, source: .manual, order: n)
                    context.insert(g)
                    g.milestone = m
                    if m.isDone || (i == 1 && n == 0) { g.setDone(true) }
                }
            }
            let s = MetricSnapshot(date: .now.addingTimeInterval(-600), visits: nums.0, socialViews: nums.1, revenue: nums.2, extras: extras)
            context.insert(s)
            s.project = p
        }
        try? context.save()
    }

    /// -PRODLINE_SNAPSHOT <path.png>: write the main window to a PNG after a moment (layout checks
    /// without screen-recording access).
    static func snapshotIfAsked(_ context: ModelContext, container: ModelContainer) {
        guard let path = UserDefaults.standard.string(forKey: "PRODLINE_SNAPSHOT") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            @MainActor func write(_ view: some View, _ suffix: String, width: CGFloat, scheme: ColorScheme) {
                let r = ImageRenderer(content: view
                    .frame(width: width)
                    .environment(\.macSnapshot, true)
                    .environment(\.colorScheme, scheme)
                    .environment(DataRefresher())
                    .environment(CelebrationCenter())
                    .environment(GitHubService())
                    .modelContainer(container))
                r.scale = 1.5
                guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: URL(fileURLWithPath: path + suffix))
            }
            let profile = (try? context.fetch(FetchDescriptor<Profile>()))?.first ?? Profile()
            let scheme: ColorScheme = UserDefaults.standard.string(forKey: "PRODLINE_SNAPSHOT_SCHEME") == "light" ? .light : .dark
            write(MacOverview(profile: profile, onOpen: { _ in }, onCreate: {}, onReview: {}), "-overview.png", width: 1180, scheme: scheme)
            if let p = projects.first(where: { $0.name == "Pixel Quest" }) ?? projects.first {
                write(MacProjectDashboard(project: p), "-project.png", width: 1180, scheme: scheme)
            }
            write(OnboardingView(profile: Profile(), wide: true).frame(height: 760), "-welcome.png", width: 1180, scheme: scheme)
            write(MenuBarPanel().background(Theme.card), "-menu.png", width: 300, scheme: scheme)
        }
    }
}
#endif
