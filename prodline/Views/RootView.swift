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
        .overlay { CelebrationOverlay() }
        .overlay {
            if showLaunch {
                LaunchView { withAnimation(.easeOut(duration: 0.4)) { showLaunch = false } }
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
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
            while !Task.isCancelled {
                await refresher.refresh(projects: projects, context: context)
                await syncGitHub()
                if let profile = profiles.first, profile.onboarded {
                    GoalEngine.afterRefresh(projects: projects, profile: profile, refresher: refresher,
                                            celebration: celebration, context: context)
                }
                WidgetPublisher.publish(projects: projects, profile: profiles.first, refresher: refresher)
                if firstPass {
                    firstPass = false
                    celebration.endCollecting(awayTitle: away > 15 * 60)
                    remindAboutLateDeadlines()
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
    static let lastBackgroundKey = "app.lastBackgroundAt"
    static let lateReminderKey = "app.lateReminderAt"

    /// On coming back: a slipped deadline resets the streak; any late checkpoint with work left gets a
    /// reminder banner (at most every 6 hours, so reopening the app doesn't nag).
    func remindAboutLateDeadlines(now: Date = .now) {
        guard let profile = profiles.first, profile.onboarded else { return }
        let slipped = ScheduleEngine.evaluateMissed(projects: projects, profile: profile, now: now)
        let late = ScheduleEngine.lateReminder(projects: projects, now: now)
        if slipped > 0 {
            celebration.nudge(title: late?.title ?? "A deadline slipped",
                              subtitle: (late.map { $0.subtitle + " · " } ?? "") + "streak reset")
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
        GitHubService.log.notice("sync: \(projects.count) projects, \(changed.count) changed")
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
                             onOpen: { opened = Opened(project: $0, cardFrame: $1) }, onCreate: { showCreate = true },
                             onStreak: { tab = .me })
                }
                tabPage(.plan) {
                    PlanView(profile: profile, onOpen: { opened = Opened(project: $0, cardFrame: nil) }, onCreate: { showCreate = true })
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

            FloatingTabBar(selection: $tab, onAdd: { showCreate = true })
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
            default: break
            }
        }
        #if DEBUG
        .onAppear {
            let d = UserDefaults.standard
            if let t = d.string(forKey: "PRODLINE_TAB").flatMap(AppTab.init(rawValue:)) { tab = t }
            if d.bool(forKey: "PRODLINE_CREATE") { showCreate = true }
            if let name = d.string(forKey: "PRODLINE_OPEN") {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    if let p = projects.first(where: { $0.name == name }) { opened = Opened(project: p, cardFrame: nil) }
                }
            }
        }
        #endif
        .sheet(isPresented: $showCreate) {
            CreateProjectFlow(profile: profile) { newID in
                tab = .projects
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { focusedID = newID }
            }
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
