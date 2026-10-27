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
            // Two weeks of history, growing toward today's numbers, so charts have something to draw.
            for d in stride(from: 14, through: 0, by: -1) {
                let f = pow(Double(15 - d) / 15, 1.6)
                let wobble = 1 + 0.06 * sin(Double(d) * 1.3)
                let s = MetricSnapshot(date: .now.addingTimeInterval(-Double(d) * 86_400 - 600),
                                       visits: (nums.0 * f * wobble).rounded(), socialViews: (nums.1 * f * wobble).rounded(),
                                       revenue: (nums.2 * f * 100).rounded() / 100,
                                       extras: extras.mapValues { ($0 * f).rounded() })
                context.insert(s)
                s.project = p
            }
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
                    .environment(\.wideLayout, true)
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
            for (w, tag) in [(CGFloat(1180), ""), (CGFloat(700), "-narrow")] {
                write(MacOverview(profile: profile, onOpen: { _ in }, onCreate: {}, onReview: {}), "-overview\(tag).png", width: w, scheme: scheme)
                if let p = projects.first(where: { $0.name == "Pixel Quest" }) ?? projects.first {
                    write(MacProjectDashboard(project: p), "-project\(tag).png", width: w, scheme: scheme)
                }
            }
            write(MacPlanView(profile: profile, onOpen: { _ in }, onCreate: {}, onIdeas: {}), "-plan.png", width: 1180, scheme: scheme)
            write(MacPlanView(profile: profile, onOpen: { _ in }, onCreate: {}, onIdeas: {}), "-plan-narrow.png", width: 700, scheme: scheme)
            write(InsightsView(wide: true).background(Theme.background), "-data.png", width: 1180, scheme: scheme)
            write(MeView(profile: profile, wide: true).background(Theme.background).environment(\.wideLayout, true), "-me.png", width: 1180, scheme: scheme)
            write(Image(nsImage: MenuBarLogo.image).resizable().interpolation(.high).frame(width: 18, height: 18).scaleEffect(4).frame(width: 90, height: 90).background(Color.white), "-logo.png", width: 90, scheme: .light)
            write(CreateProjectFlow(profile: profile) { _ in }.environment(\.wideLayout, true).frame(height: 680), "-create.png", width: 980, scheme: scheme)
            write(IntegrationPicker(connected: [.stripe]) { _ in }.environment(\.wideLayout, true).frame(height: 640), "-picker.png", width: 860, scheme: scheme)
            if let p = projects.first {
                write(IntegrationEditor(project: p, integration: Integration(kind: .plausible), isNew: true).environment(\.wideLayout, true).frame(height: 600), "-editor.png", width: 860, scheme: scheme)
            }
            if let p = projects.first(where: { $0.name == "Pixel Quest" }) {
                write(VerdictSheet(project: p).environment(\.wideLayout, true).frame(height: 640), "-verdict.png", width: 900, scheme: scheme)
                write(EditProjectSheet(project: p).environment(\.wideLayout, true).frame(height: 620), "-edit.png", width: 820, scheme: scheme)
                write(ShareCardSheet(project: p).environment(\.wideLayout, true).frame(height: 640), "-share.png", width: 760, scheme: scheme)
                write(ConnectionSheet(project: p).environment(\.wideLayout, true).frame(height: 640), "-connection.png", width: 860, scheme: scheme)
            }
            let center = CelebrationCenter()
            center.fire(title: "+10 XP", subtitle: "Nailed it · right on time", accent: Accent(hex: 0xA35CFF), confetti: false)
            write(ZStack { Theme.background; CelebrationOverlay() }.environment(center).environment(\.wideLayout, true).frame(height: 420), "-toast.png", width: 900, scheme: scheme)
            write(OnboardingView(profile: Profile(), wide: true).frame(height: 760), "-welcome.png", width: 1180, scheme: scheme)
            write(MenuBarPanel().background(Theme.card), "-menu.png", width: 300, scheme: scheme)
        }
    }
}
#endif
