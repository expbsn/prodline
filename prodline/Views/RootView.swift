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
                    MainTabs(profile: profile)
                        .transition(.opacity)
                } else {
                    OnboardingView(profile: profile)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: profiles.first?.onboarded)
        .overlay { CelebrationOverlay() }
        .environment(refresher)
        .environment(celebration)
        .onAppear {
            if profiles.isEmpty {
                context.insert(Profile())
                try? context.save()
            }
        }
        // Foreground polling: runs only while the app is active, restarts on every activation.
        .task(id: phase) {
            guard phase == .active else {
                if phase == .background { DataRefresher.scheduleBackgroundRefresh() }
                return
            }
            if let profile = profiles.first, profile.onboarded {
                let missed = ScheduleEngine.evaluateMissed(projects: projects, profile: profile)
                if missed > 0 {
                    celebration.nudge(title: "Deadline slipped",
                                      subtitle: "No worries — your streak restarts with the next one. You've got this!")
                }
            }
            while !Task.isCancelled {
                await refresher.refresh(projects: projects, context: context)
                try? await Task.sleep(for: DataRefresher.foregroundInterval)
            }
        }
    }
}

struct MainTabs: View {
    let profile: Profile

    var body: some View {
        TabView {
            Tab("Today", systemImage: "flame.fill") { TodayView(profile: profile) }
            Tab("Projects", systemImage: "square.stack.3d.up.fill") { ProjectsView(profile: profile) }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") { InsightsView() }
            Tab("Me", systemImage: "person.fill") { MeView(profile: profile) }
        }
        .tint(Theme.blue)
    }
}
