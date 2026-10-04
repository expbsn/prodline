import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var projects: [Project]

    @State private var refresher = DataRefresher()
    @State private var celebration = CelebrationCenter()

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
        .environment(refresher)
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
            #endif
        }
        // Foreground polling: runs only while the app is active, restarts on every activation.
        .task(id: phase) {
            guard phase == .active else {
                if phase == .background { DataRefresher.scheduleBackgroundRefresh() }
                return
            }
            if let profile = profiles.first, profile.onboarded {
                if ScheduleEngine.evaluateMissed(projects: projects, profile: profile) > 0 {
                    celebration.nudge(title: "A deadline slipped",
                                      subtitle: "Streak reset. The next checkpoint starts a new one.")
                }
            }
            while !Task.isCancelled {
                await refresher.refresh(projects: projects, context: context)
                try? await Task.sleep(for: DataRefresher.foregroundInterval)
            }
        }
    }
}

/// Tabs + floating tab bar + global sheets.
struct MainShell: View {
    let profile: Profile
    @Query(sort: \Project.startDate) private var projects: [Project]

    @State private var tab: AppTab = .projects
    @State private var focusedID: UUID?
    @State private var showCreate = false
    @State private var opened: Project?
    @Namespace private var zoom

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .projects:
                    HomeView(profile: profile, focusedID: $focusedID, zoom: zoom,
                             onOpen: { opened = $0 }, onCreate: { showCreate = true },
                             onStreak: { tab = .me })
                case .plan:
                    PlanView(profile: profile, onOpen: { opened = $0 }, onCreate: { showCreate = true })
                case .insights:
                    InsightsView()
                case .me:
                    MeView(profile: profile)
                }
            }
            .safeAreaPadding(.bottom, 92)
            .transition(.opacity)

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
        }
        .ignoresSafeArea(.keyboard)
        #if DEBUG
        .onAppear {
            let d = UserDefaults.standard
            if let t = d.string(forKey: "PRODLINE_TAB").flatMap(AppTab.init(rawValue:)) { tab = t }
            if d.bool(forKey: "PRODLINE_CREATE") { showCreate = true }
            if let name = d.string(forKey: "PRODLINE_OPEN") {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    opened = projects.first { $0.name == name }
                }
            }
        }
        #endif
        .fullScreenCover(item: $opened) { p in
            ProjectDetailView(project: p)
                .navigationTransition(.zoom(sourceID: p.id, in: zoom))
        }
        .sheet(isPresented: $showCreate) {
            CreateProjectFlow(profile: profile) { newID in
                tab = .projects
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { focusedID = newID }
            }
        }
    }
}
