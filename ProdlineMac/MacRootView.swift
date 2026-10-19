import SwiftUI
import SwiftData
import AppKit

/// The Mac window: a sidebar with the iPhone app's tabs and your projects; the content is the iPhone
/// app's own screens, so the design is the same. Runs the same sync loop as the iPhone (integrations,
/// GitHub, goals, XP), so the Mac works on its own; iCloud keeps both in step.
struct MacRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \Project.startDate) private var projects: [Project]

    @Environment(DataRefresher.self) private var refresher
    @Environment(GitHubService.self) private var github
    @Environment(CelebrationCenter.self) private var celebration

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let profile = profiles.first {
                if profile.onboarded {
                    MacShell(profile: profile)
                } else {
                    OnboardingView(profile: profile)
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .overlay { ShipOverlay() }
        .overlay { StreakOverlay() }
        .overlay { CelebrationOverlay() }
        .onAppear {
            if profiles.isEmpty {
                context.insert(Profile())
                try? context.save()
            }
            #if DEBUG
            MacDemo.seedIfNeeded(context)
            MacDemo.snapshotIfAsked(context, container: ProdlineMacApp.container)
            #endif
        }
        .onChange(of: phase, initial: true) { Cheer.appIsOpen = phase == .active }
        // While a window is open: numbers, GitHub and goals every few seconds, like the iPhone in the foreground.
        .task {
            var firstPass = true
            celebration.beginCollecting()
            while !Task.isCancelled {
                await refresher.refresh(projects: projects, context: context)
                await syncGitHub()
                if let profile = profiles.first, profile.onboarded {
                    GoalEngine.afterRefresh(projects: projects, profile: profile, refresher: refresher,
                                            celebration: celebration, context: context)
                }
                if firstPass {
                    firstPass = false
                    celebration.endCollecting(awayTitle: false)
                    if let profile = profiles.first, profile.onboarded {
                        ScheduleEngine.evaluateMissed(projects: projects, profile: profile)
                    }
                }
                try? await Task.sleep(for: .seconds(AppSettings.refreshSeconds))
            }
        }
    }

    private func syncGitHub() async {
        let changed = await github.refresh(projects: projects, force: false)
        for p in changed {
            if let snap = github.snapshots[p.id] { GoalEngine.syncGitHub(snap, project: p, context: context) }
        }
    }
}

enum MacPage: Hashable {
    case tab(AppTab)
    case project(UUID)
}

struct MacShell: View {
    let profile: Profile
    @Query(sort: \Project.startDate) private var projects: [Project]
    @State private var page: MacPage? = .tab(.projects)
    @State private var focusedID: UUID?
    @State private var showCreate = false
    @State private var showLimit = false
    @State private var showIdeas = false
    @State private var showReview = false
    @State private var startingIdea: Idea?
    @Namespace private var zoom

    private var activeProjects: [Project] { projects.filter { $0.phase() != .finished }.reversed() }
    private var finishedProjects: [Project] { projects.filter { $0.phase() == .finished }.reversed() }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    ForEach(AppTab.allCases) { t in
                        Label(t.title, systemImage: t.symbol(selected: page == .tab(t))).tag(MacPage.tab(t))
                    }
                }
                Section("Projects") {
                    ForEach(activeProjects) { p in projectRow(p) }
                }
                if !finishedProjects.isEmpty {
                    Section("Finished") {
                        ForEach(finishedProjects) { p in projectRow(p) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                Button { requestCreate() } label: {
                    Label("New project", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky(.accent, height: 40))
                .environment(\.accent, .neutral)
                .padding(12)
            }
        } detail: {
            detail
                .background(Theme.background)
                .environment(\.isActiveTab, true)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { requestCreate() } label: { Image(systemName: "plus") }.help("New project")
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: { startingIdea = nil }) {
            CreateProjectFlow(profile: profile, idea: startingIdea) { newID in
                page = .project(newID)
            }
            .frame(width: 460, height: 760)
        }
        .sheet(isPresented: $showLimit) { BuildLimitSheet(profile: profile).frame(width: 460, height: 560) }
        .sheet(isPresented: $showIdeas) {
            IdeaInboxSheet(profile: profile) { idea in
                showIdeas = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    requestCreate(from: idea)
                }
            }
            .frame(width: 460, height: 640)
        }
        .sheet(isPresented: $showReview) {
            WeeklyReviewView(stats: WeeklyReview.make(projects: projects, profile: profile, weekStart: WeeklyReview.reviewWeekStart()),
                             profile: profile) { showReview = false }
                .frame(width: 440, height: 820)
        }
        .onReceive(NotificationCenter.default.publisher(for: WeeklyReview.open)) { _ in showReview = true }
        .onReceive(NotificationCenter.default.publisher(for: .macNewProject)) { _ in requestCreate() }
        #if DEBUG
        .onAppear {
            if let name = UserDefaults.standard.string(forKey: "PRODLINE_OPEN"), let p = projects.first(where: { $0.name == name }) {
                page = .project(p.id)
            }
            if let t = UserDefaults.standard.string(forKey: "PRODLINE_TAB").flatMap(AppTab.init(rawValue:)) { page = .tab(t) }
        }
        #endif
    }

    private func projectRow(_ p: Project) -> some View {
        HStack(spacing: 10) {
            ProjectThumb(project: p, size: 24)
            Text(p.name).lineLimit(1)
            Spacer(minLength: 0)
            if let m = p.nextMilestone, m.isDueToday || m.isOverdue {
                Circle().fill(m.isOverdue ? Theme.danger : Theme.flame).frame(width: 7, height: 7)
                    .help(m.isOverdue ? "Checkpoint overdue" : "Checkpoint due today")
            }
        }
        .tag(MacPage.project(p.id))
    }

    /// The iPhone screens are made for a phone's width; on the Mac they sit in a centered column.
    @ViewBuilder
    private var detail: some View {
        switch page {
        case .tab(.projects), nil:
            column(560) {
                HomeView(profile: profile, focusedID: $focusedID, zoom: zoom,
                         onOpen: { p, _ in page = .project(p.id) }, onCreate: { requestCreate() },
                         onStreak: { page = .tab(.me) }, onReview: { showReview = true },
                         onFeedback: { NSWorkspace.shared.open(URL(string: "mailto:info@prodline.build?subject=Prodline%20for%20Mac%20feedback")!) })
            }
        case .tab(.plan):
            column(640) {
                PlanView(profile: profile, onOpen: { page = .project($0.id) }, onCreate: { requestCreate() },
                         onIdeas: { showIdeas = true })
            }
        case .tab(.insights):
            column(640) { InsightsView() }
        case .tab(.me):
            column(600) { MeView(profile: profile) }
        case .project(let id):
            if let p = projects.first(where: { $0.id == id }) {
                column(620) {
                    ProjectDetailView(project: p, cardFrame: nil, onClose: { page = .tab(.projects) })
                        .id(p.id)
                }
            } else {
                ContentUnavailableView("Project not found", systemImage: "questionmark.folder")
            }
        }
    }

    private func column<C: View>(_ width: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestCreate(from idea: Idea? = nil) {
        if ProjectLimit.isFull(projects, profile: profile) {
            showLimit = true
        } else {
            startingIdea = idea
            showCreate = true
        }
    }
}

extension Notification.Name {
    static let macNewProject = Notification.Name("prodline.mac.newProject")
}

struct StreakBadge: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
            Text("\(streak)").monospacedDigit()
        }
        .foregroundStyle(streak > 0 ? Theme.flame : Theme.secondary)
        .font(.display(15, 750))
        .help("\(streak)-day streak")
    }
}
