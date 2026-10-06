import SwiftUI
import SwiftData
import OSLog

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var projects: [Project]

    @State private var refresher = DataRefresher()
    @State private var github = GitHubService()
    @State private var celebration = CelebrationCenter()
    /// Only on a fresh launch: @State survives backgrounding, so foregrounding never replays it.
    @State private var showLaunch = LaunchGate.shouldShow

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let profile = profiles.first {
                if profile.onboarded {
                    MainShell(profile: profile)
                        .transition(.opacity)
                } else {
                    OnboardingView(profile: profile)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: profiles.first?.onboarded)
        // The ship moment under the banners and confetti, so the confetti falls over it.
        .overlay { ShipOverlay() }
        .overlay { CelebrationOverlay() }
        .overlay {
            if showLaunch {
                LaunchView { withAnimation(.easeOut(duration: 0.4)) { showLaunch = false } }
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        // Ticking a goal updates the deadline Live Activity right away, not on the next sync.
        .onChange(of: deadlineSignature) { Task { await LiveActivities.sync(projects) } }
        // A widget tick that ran in the app's own process: apply it now rather than on the next pass.
        .onReceive(NotificationCenter.default.publisher(for: WidgetTicks.didRecord)) { _ in
            guard let profile = profiles.first, profile.onboarded,
                  WidgetPublisher.applyWidgetTicks(projects: projects, profile: profile) else { return }
            GoalEngine.afterRefresh(projects: projects, profile: profile, refresher: refresher,
                                    celebration: celebration, context: context)
            WidgetPublisher.publish(projects: projects, profile: profile, refresher: refresher)
        }
        .onReceive(NotificationCenter.default.publisher(for: LaunchGate.replay)) { _ in showLaunch = true }
        .environment(refresher)
        .environment(github)
        .environment(celebration)
        .onAppear {
            if profiles.isEmpty {
                context.insert(Profile())
                try? context.save()
            }
            #if DEBUG
            // UI-testing hooks:  -PRODLINE_DEMO YES  -PRODLINE_TAB plan  -PRODLINE_OPEN "Pixel Quest"  -PRODLINE_CREATE YES
            if UserDefaults.standard.bool(forKey: "PRODLINE_DEMO"), projects.isEmpty,
               let profile = profiles.first ?? (try? context.fetch(FetchDescriptor<Profile>()))?.first {
                profile.onboarded = true
                profile.remindersEnabled = false
                DemoData.load(baseURL: UserDefaults.standard.string(forKey: "mockServerURL") ?? "http://127.0.0.1:8787",
                              profile: profile, context: context)
            }
            if UserDefaults.standard.bool(forKey: "PRODLINE_LIVE") { Task { await LiveActivities.demo() } }
            if UserDefaults.standard.bool(forKey: "PRODLINE_SHIP") {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    celebration.celebrateShip(.init(daysEarly: 4, project: "Habit Hero", accent: Accent(hex: 0x58CC02), xp: 70))
                }
            }
            if UserDefaults.standard.bool(forKey: "PRODLINE_BANNER") {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    celebration.fire(title: "+10 XP", subtitle: "Nailed it · just a test",
                                     accent: projects.first?.accent ?? Accent(hex: 0x58CC02))
                }
            }
            #endif
        }
        // Foreground polling: runs only while the app is active, restarts on every activation.
        .task(id: phase) {
            guard phase == .active else {
                if phase == .background {
                    UserDefaults.standard.set(Date.now, forKey: Self.lastBackgroundKey)
                    DataRefresher.scheduleBackgroundRefresh()
                    WidgetPublisher.publish(projects: projects, profile: profiles.first, refresher: refresher)
                    Task { await LiveActivities.sync(projects) }
                }
                return
            }
            // Let the splash play on an idle main thread and keep banners for after it.
            while showLaunch, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(150)) }
            // XP earned while the app was closed (goals ticked in prodline.json, issues closed, targets hit)
            // arrives in the first sync; sum it up in one banner instead of a burst.
            let away = Date.now.timeIntervalSince(UserDefaults.standard.object(forKey: Self.lastBackgroundKey) as? Date ?? .distantPast)
            celebration.beginCollecting()
            var firstPass = true
            GitHubService.trace("loop start, \(projects.count) projects")
            while !Task.isCancelled {
                WidgetPublisher.applyWidgetTicks(projects: projects, profile: profiles.first)
                await refresher.refresh(projects: projects, context: context)
                await syncGitHub()
                if let profile = profiles.first, profile.onboarded {
                    GoalEngine.afterRefresh(projects: projects, profile: profile, refresher: refresher,
                                            celebration: celebration, context: context)
                }
                WidgetPublisher.publish(projects: projects, profile: profiles.first, refresher: refresher)
                await LiveActivities.sync(projects)
                if firstPass {
                    firstPass = false
                    celebration.endCollecting(awayTitle: away > 15 * 60)
                    remindAboutLateDeadlines()
                    nudgeAboutFreeSlot()
                    WeeklyReview.scheduleNotification(enabled: profiles.first?.remindersEnabled ?? false)
                    if let profile = profiles.first, profile.remindersEnabled {
                        for p in projects { Notifier.scheduleVerdict(p, hour: profile.reminderHour) }
                    }
                }
                try? await Task.sleep(for: .seconds(AppSettings.refreshSeconds))
            }
            // Backgrounded mid-sync: release whatever was held rather than swallowing later banners.
            if firstPass { celebration.endCollecting(awayTitle: false) }
        }
    }
}

/// Tabs + floating tab bar + global sheets.
extension RootView {
    /// Changes whenever a goal or checkpoint due today changes.
    private var deadlineSignature: String {
        var parts: [String] = []
        for (_, m) in LiveActivities.candidates(projects) {
            parts.append(m.id.uuidString + m.title)
            for g in m.sortedGoals { parts.append(g.title + (g.isDone ? "1" : "0")) }
        }
        let today = Date.now.startOfDay
        for p in projects {
            for m in p.milestones ?? [] where m.isDone && m.dueDate == today { parts.append(m.id.uuidString) }
        }
        return parts.joined(separator: "|")
    }

    static let lastBackgroundKey = "app.lastBackgroundAt"
    static let lateReminderKey = "app.lateReminderAt"
    static let slotNudgeKey = "app.slotNudgeAt"

    /// A build slot is free and ideas are waiting: say so, at most every few days.
    func nudgeAboutFreeSlot() {
        guard let profile = profiles.first, profile.onboarded, profile.buildLimit > 0,
              (ProjectLimit.freeSlots(projects, profile: profile) ?? 0) > 0 else { return }
        let waiting = ((try? context.fetch(FetchDescriptor<Idea>())) ?? []).filter { $0.startedAt == nil }
        guard !waiting.isEmpty else { return }
        let last = UserDefaults.standard.object(forKey: Self.slotNudgeKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 3 * 86_400 else { return }
        UserDefaults.standard.set(Date.now, forKey: Self.slotNudgeKey)
        celebration.nudge(title: "A build slot is free",
                          subtitle: waiting.count == 1 ? "\(waiting[0].title) is waiting in your idea inbox." : "\(waiting.count) ideas are waiting in your inbox.")
    }

    /// On coming back: a slipped deadline or any late checkpoint with work left gets a
    /// reminder banner (at most every 6 hours, so reopening the app doesn't nag).
    func remindAboutLateDeadlines(now: Date = .now) {
        guard let profile = profiles.first, profile.onboarded else { return }
        let slipped = ScheduleEngine.evaluateMissed(projects: projects, profile: profile, now: now)
        let late = ScheduleEngine.lateReminder(projects: projects, now: now)
        if slipped > 0 {
            celebration.nudge(title: late?.title ?? "A deadline slipped",
                              subtitle: late?.subtitle ?? "Finish it late: it still earns XP.")
            UserDefaults.standard.set(now, forKey: Self.lateReminderKey)
            return
        }
        guard let late else { return }
        let last = UserDefaults.standard.object(forKey: Self.lateReminderKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) > 6 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: Self.lateReminderKey)
        celebration.nudge(title: late.title, subtitle: late.subtitle)
    }

    /// GitHub issues → goals, plus the "repo has gone quiet" nudge.
    func syncGitHub() async {
        let changed = await github.refresh(projects: projects)
        GitHubService.trace("sync: \(projects.count) projects, \(changed.count) changed")
        guard let profile = profiles.first else { return }
        for p in changed {
            if let snap = github.snapshots[p.id] { GoalEngine.syncGitHub(snap, project: p, context: context) }
            if profile.remindersEnabled {
                Notifier.staleRepoNudge(project: p, hour: profile.reminderHour)
                for m in p.sortedMilestones where !m.isDone { Notifier.schedule(m, hour: profile.reminderHour) }
            }
        }
    }
}

struct MainShell: View {
    let profile: Profile
    @Query(sort: \Project.startDate) private var projects: [Project]

    @State private var tab: AppTab = .projects
    @State private var focusedID: UUID?
    @State private var showCreate = false
    @State private var showLimit = false
    @State private var showIdeas = false
    @State private var showReview = false
    /// The idea the create flow starts from, if any.
    @State private var startingIdea: Idea?
    @State private var opened: Opened?
    @Namespace private var zoom

    private func tabPage<Content: View>(_ t: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        let active = tab == t
        return content()
            .environment(\.isActiveTab, active)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }

    struct Opened: Equatable {
        let project: Project
        let cardFrame: CGRect?
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // All tabs stay alive so each keeps its scroll position (Dash's carousel never has to re-center).
            ZStack {
                tabPage(.projects) {
                    HomeView(profile: profile, focusedID: $focusedID, zoom: zoom,
                             onOpen: { opened = Opened(project: $0, cardFrame: $1) }, onCreate: { requestCreate() },
                             onStreak: { tab = .me }, onReview: { showReview = true })
                }
                tabPage(.plan) {
                    PlanView(profile: profile, onOpen: { opened = Opened(project: $0, cardFrame: nil) }, onCreate: { requestCreate() },
                             onIdeas: { showIdeas = true })
                }
                tabPage(.insights) { InsightsView() }
                tabPage(.me) { MeView(profile: profile) }
            }
            .safeAreaPadding(.bottom, 92)

            // Fade content out behind the tab bar, all the way to the screen edge.
            VStack(spacing: 0) {
                Spacer()
                // Eased stops so the fade starts imperceptibly instead of with a visible edge.
                LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                                       .init(color: Theme.background.opacity(0.06), location: 0.2),
                                       .init(color: Theme.background.opacity(0.28), location: 0.4),
                                       .init(color: Theme.background.opacity(0.62), location: 0.58),
                                       .init(color: Theme.background.opacity(0.9), location: 0.72),
                                       .init(color: Theme.background, location: 0.82)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            FloatingTabBar(selection: $tab, onAdd: { requestCreate() })
                .padding(.bottom, 2)

            if let o = opened {
                ProjectDetailView(project: o.project, cardFrame: o.cardFrame, onClose: { opened = nil })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(.keyboard)
        // Widget taps: prodline://project/<id> opens that project, prodline://data/<metric> the Data tab.
        .onOpenURL { url in
            guard url.scheme == "prodline" else { return }
            switch url.host() {
            case "project":
                let id = url.lastPathComponent
                if let p = projects.first(where: { $0.id.uuidString == id }) {
                    tab = .projects
                    focusedID = p.id
                    opened = Opened(project: p, cardFrame: nil)
                }
            case "data":
                opened = nil
                tab = .insights
            case "review":
                opened = nil
                showReview = true
            default: break
            }
        }
        #if DEBUG
        .onAppear {
            let d = UserDefaults.standard
            if let t = d.string(forKey: "PRODLINE_TAB").flatMap(AppTab.init(rawValue:)) { tab = t }
            if d.bool(forKey: "PRODLINE_CREATE") { showCreate = true }
            if d.bool(forKey: "PRODLINE_REVIEW") { showReview = true }
            if let name = d.string(forKey: "PRODLINE_OPEN") {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    if let p = projects.first(where: { $0.name == name }) { opened = Opened(project: p, cardFrame: nil) }
                }
            }
        }
        #endif
        .sheet(isPresented: $showCreate, onDismiss: { startingIdea = nil }) {
            CreateProjectFlow(profile: profile, idea: startingIdea) { newID in
                tab = .projects
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { focusedID = newID }
            }
        }
        .sheet(isPresented: $showLimit) { BuildLimitSheet(profile: profile) }
        .fullScreenCover(isPresented: $showReview) {
            WeeklyReviewView(stats: WeeklyReview.make(projects: projects, profile: profile, weekStart: WeeklyReview.reviewWeekStart()),
                             profile: profile) { showReview = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: WeeklyReview.open)) { _ in
            opened = nil
            showReview = true
        }
        .sheet(isPresented: $showIdeas) {
            IdeaInboxSheet(profile: profile) { idea in
                showIdeas = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    requestCreate(from: idea)
                }
            }
        }
    }

    /// New project, unless every build slot is taken: then the idea gets parked instead.
    private func requestCreate(from idea: Idea? = nil) {
        if ProjectLimit.isFull(projects, profile: profile) {
            Haptics.warning()
            showLimit = true
        } else {
            startingIdea = idea
            showCreate = true
        }
    }
}

enum LaunchGate {
    static let replay = Notification.Name("prodline.replayLaunch")
    static var shouldShow: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "PRODLINE_NOLAUNCH") { return false }
        #endif
        return !UIAccessibility.isReduceMotionEnabled
    }
}

extension EnvironmentValues {
    /// False for tabs kept alive in the background.
    @Entry var isActiveTab: Bool = true
}
