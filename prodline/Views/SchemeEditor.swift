import SwiftUI
import SwiftData
import UserNotifications

/// The user's custom building scheme (phase lengths, cadence, checkpoint weekdays).
struct SchemeEditor: View {
    @Bindable var profile: Profile

    private let days: [(Int, String)] = [(2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa"), (1, "Su")]

    private var overlap: Int {
        Int((Double(profile.buildDays + profile.observeDays) / Double(max(profile.newProjectEveryDays, 1))).rounded(.up))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            row("Build phase", profile.buildDays.durationText) {
                ChunkySlider(value: $profile.buildDays, range: 3...42)
            }
            row("Observe phase", profile.observeDays.durationText) {
                ChunkySlider(value: $profile.observeDays, range: 7...90)
            }
            row("New project every", profile.newProjectEveryDays.durationText) {
                ChunkySlider(value: $profile.newProjectEveryDays, range: 3...42)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Checkpoint days").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    ForEach(days, id: \.0) { wd, label in
                        Chip(title: label, isOn: profile.hasWeekday(wd)) { profile.toggleWeekday(wd) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            SchemePreview(build: profile.buildDays, observe: profile.observeDays, every: profile.newProjectEveryDays)
            Text("A new project every \(profile.newProjectEveryDays.durationText): \(profile.buildDays.durationText) building, then \(profile.observeDays.durationText) watching traction. About \(overlap) project\(overlap == 1 ? "" : "s") run at once.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<C: View>(_ title: String, _ value: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).display(20, 700).foregroundStyle(Theme.ink).contentTransition(.numericText())
            }
            content()
        }
    }
}

/// Mini Gantt of how projects overlap with the current scheme.
struct SchemePreview: View {
    let build: Int, observe: Int, every: Int

    var body: some View {
        GeometryReader { geo in
            let span = Double(every * 3 + build + observe)
            let w = geo.size.width
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<4) { i in
                    let x = Double(i * every) / span * w
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.ink).frame(width: Double(build) / span * w)
                        Capsule().fill(Theme.ink.opacity(0.18)).frame(width: Double(observe) / span * w)
                    }
                    .frame(height: 9)
                    .offset(x: x)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: build + observe * 100 + every * 10000)
        }
        .frame(height: 4 * 9 + 3 * 5)
        .accessibilityHidden(true)
    }
}

struct MeView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Environment(GitHubService.self) private var github
    @Query private var projects: [Project]
    @AppStorage("mockServerURL") private var mockServerURL = "http://127.0.0.1:8787"
    @AppStorage(AppSettings.Key.refreshSeconds) private var refreshSeconds = 30
    @AppStorage(AppSettings.Key.githubMinutes) private var githubMinutes = 10
    @AppStorage(AppSettings.Key.commitWatch) private var commitWatch = true
    @AppStorage(AppSettings.Key.suggestions) private var suggestions = true
    @AppStorage(AppSettings.Key.sampleData) private var sampleData = true
    @AppStorage(AppSettings.Key.haptics) private var haptics = true
    @State private var confirm: Confirm?

    private enum Confirm: Identifiable {
        case deleteAll, resetProgress
        var id: Self { self }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Level \(profile.level)", title: "Me")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(profile.xp % 100) / 100 XP to level \(profile.level + 1)").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Best streak \(profile.bestStreak)").font(.ui(13)).foregroundStyle(Theme.secondary)
                    }
                    ChunkyProgressBar(value: profile.levelProgress, color: Color(hex: 0xFFC800))
                }
                .card()
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle("Building scheme")
                    SchemeEditor(profile: profile)
                    Label("Applies to projects you create from now on.", systemImage: "info.circle")
                        .font(.ui(12)).foregroundStyle(Theme.secondary)
                }
                .card()
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Reminders")
                    Toggle(isOn: $profile.remindersEnabled) {
                        Text("Deadline notifications").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.ink)
                    .onChange(of: profile.remindersEnabled) { _, on in
                        Haptics.select()
                        Task {
                            if on { _ = await Notifier.requestAuth() }
                            Notifier.rescheduleAll(projects: projects, profile: profile)
                        }
                    }
                    if profile.remindersEnabled {
                        HStack {
                            Text("Morning reminder").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(String(format: "%02d:00", profile.reminderHour)).display(20, 700).foregroundStyle(Theme.ink)
                        }
                        ChunkySlider(value: $profile.reminderHour, range: 5...12)
                            .onChange(of: profile.reminderHour) { Notifier.rescheduleAll(projects: projects, profile: profile) }
                    }
                }
                .card()
                .padding(.horizontal, 16)

                configurationCard.padding(.horizontal, 16)

                developerCard.padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .confirmationDialog(confirm == .deleteAll ? "Delete all data?" : "Reset progress?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { c in
            switch c {
            case .deleteAll: Button("Delete everything", role: .destructive, action: deleteAll)
            case .resetProgress: Button("Reset XP and streaks", role: .destructive, action: resetProgress)
            }
        } message: { c in
            Text(c == .deleteAll
                 ? "Removes every project, its deadlines, goals, metrics and stored keys, and resets your progress. This can't be undone."
                 : "Sets XP, level, streak and on-time stats back to zero. Projects stay.")
        }
    }

    // MARK: Configuration

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Configuration")

            optionRow("Live refresh", "How often numbers update while the app is open.") {
                HStack(spacing: 6) {
                    ForEach([(15, "15s"), (30, "30s"), (60, "1m"), (120, "2m")], id: \.0) { v, label in
                        Chip(title: label, isOn: refreshSeconds == v) { refreshSeconds = v }
                    }
                }
            }
            optionRow("GitHub full sync", "Issues, README and prodline.json.") {
                HStack(spacing: 6) {
                    ForEach([(5, "5m"), (10, "10m"), (30, "30m")], id: \.0) { v, label in
                        Chip(title: label, isOn: githubMinutes == v) { githubMinutes = v }
                    }
                }
            }
            toggleRow("Watch repos for new commits", "Syncs right after you push: ~30 s with a token, ~2 min without.", $commitWatch)
            toggleRow("Suggested goals", GoalPlanner.isAvailable
                      ? "Drafted on this iPhone with Apple Intelligence."
                      : "Needs Apple Intelligence on this iPhone.", $suggestions)
            toggleRow("Sample data", "Show sample numbers for projects without an endpoint.", $sampleData)
            toggleRow("Haptics", "Taps and buzzes on buttons, sliders and wins.", $haptics)
        }
        .card()
        .environment(\.accent, .neutral)
    }

    private func optionRow<C: View>(_ title: String, _ caption: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
            Text(caption).font(.ui(13)).foregroundStyle(Theme.secondary)
            control()
        }
    }

    private func toggleRow(_ title: String, _ caption: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                Text(caption).font(.ui(13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.ink)
        .onChange(of: value.wrappedValue) { Haptics.select() }
    }

    // MARK: Demo & testing actions

    private func refreshAll() {
        Task {
            await refresher.refresh(projects: projects, context: context, force: true)
            let changed = await github.refresh(projects: projects, force: true)
            for p in changed {
                if let snap = github.snapshots[p.id] { GoalEngine.syncGitHub(snap, project: p, context: context) }
            }
            GoalEngine.afterRefresh(projects: projects, profile: profile, refresher: refresher,
                                    celebration: celebration, context: context)
            celebration.fire(title: "Refreshed", subtitle: "Metrics and \(changed.count) repo\(changed.count == 1 ? "" : "s") updated", confetti: false)
        }
    }

    private func simulateSale() {
        guard let p = projects.first(where: { $0.hasEndpoint && $0.isActive }),
              var comps = URLComponents(string: p.endpoint),
              let key = Keychain.get(p.id.uuidString) else {
            celebration.nudge(title: "No connected project", subtitle: "Load the demo projects first.")
            return
        }
        // …/projects/<slug>/metrics → …/projects/<slug>/events
        comps.path = comps.path.replacingOccurrences(of: "/metrics", with: "/events")
        comps.query = nil
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data(#"{"type":"sale","amount":49}"#.utf8)
        Task {
            _ = try? await URLSession.shared.data(for: req)
            await refresher.refresh(projects: [p], context: context, force: true)
            celebration.fire(title: "+$49 sale", subtitle: "Simulated on \(p.name)", accent: p.accent)
        }
    }

    private func resetProgress() {
        profile.xp = 0; profile.streak = 0; profile.bestStreak = 0
        profile.completedOnTime = 0; profile.completedLate = 0
        try? context.save()
        Haptics.warning()
    }

    private func deleteAll() {
        for p in projects {
            Keychain.delete(p.id.uuidString)
            Keychain.delete("gh-" + p.id.uuidString)
            context.delete(p)
        }
        resetProgress()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        refresher.reset()
        github.reset()
        DashLayout.lastCardFrame = nil
        try? context.save()
    }

    private func devButton(_ title: String, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 22)
                Text(title).font(.ui(15, .semibold))
                Spacer()
            }
            .foregroundStyle(role == .destructive ? Theme.danger : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.background))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Demo & testing")
            Text("Run `python3 MockProject/server.py` on your Mac, then load demo projects that stream data from it.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
            TextField("Mock server URL", text: $mockServerURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .inputField()
            Button("Load demo projects") {
                DemoData.load(baseURL: mockServerURL, profile: profile, context: context)
                celebration.fire(title: "Demo loaded", subtitle: "\(DemoData.projects.count) projects connected to the mock server")
                Task { await refresher.refresh(projects: projects, context: context, force: true) }
            }
            .buttonStyle(.chunky(.neutral, height: 50))

            VStack(spacing: 8) {
                devButton("Refresh everything now", "arrow.clockwise", action: refreshAll)
                devButton("Simulate a $49 sale", "dollarsign.circle", action: simulateSale)
                devButton("Send a test notification (5 s)", "bell.badge") {
                    Task {
                        _ = await Notifier.requestAuth()
                        Notifier.sendTest(projects: projects)
                        celebration.fire(title: "Notification queued", subtitle: "Lock the phone or leave the app to see it", confetti: false)
                    }
                }
                devButton("Play a celebration", "party.popper") {
                    celebration.fire(title: "+10 XP", subtitle: "\(ScheduleEngine.praise()) · just a test", accent: projects.first?.accent ?? .neutral)
                }
                devButton("Show the missed-deadline nudge", "exclamationmark.bubble") {
                    celebration.nudge(title: "A deadline slipped", subtitle: "Streak reset. The next checkpoint starts a new one.")
                }
                devButton("Replay launch animation", "play.circle") {
                    NotificationCenter.default.post(name: LaunchGate.replay, object: nil)
                }
                devButton("Replay onboarding", "sparkles.rectangle.stack") {
                    profile.onboarded = false
                    try? context.save()
                }
                devButton("Reset XP and streaks", "arrow.uturn.backward", role: .destructive) { confirm = .resetProgress }
                devButton("Delete all data", "trash", role: .destructive) { confirm = .deleteAll }
            }
        }
        .card()
    }
}

struct OnboardingView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @State private var step = 0
    @State private var fanned = false

    var body: some View {
        VStack(spacing: 0) {
            ChunkyProgressBar(value: Double(step + 1) / 3, color: Theme.ink, height: 12)
                .padding(.horizontal, 24).padding(.top, 14)

            ScrollView(showsIndicators: false) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: scheme
                    default: reminders
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)
            .bottomActionBar {
                Button(step == 2 ? "Turn on reminders" : (step == 0 ? "Get started" : "Continue"), action: next)
                    .buttonStyle(.chunky)
                if step == 2 {
                    Button("Not now") { profile.remindersEnabled = false; finish() }
                        .font(.ui(15, .semibold)).foregroundStyle(Theme.secondary)
                        .frame(height: 32)
                        .padding(.horizontal, 4)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                ForEach(Array(Self.sampleCards.enumerated()), id: \.offset) { i, c in
                    ProjectCardFace(name: c.name, initial: String(c.name.prefix(1)), accent: c.accent, cover: c.cover,
                                    cornerLabel: "Day", cornerValue: "\(c.day)", footnote: c.phase)
                        .frame(width: 200)
                        .rotationEffect(.degrees(fanned ? Double(i - 1) * 7 : 0), anchor: .bottom)
                        .offset(x: fanned ? CGFloat(i - 1) * 30 : 0, y: fanned ? abs(CGFloat(i - 1)) * 10 : 0)
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .padding(.top, 8)
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.15)) { fanned = true }
            }

            Text("Welcome to").eyebrow()
            Text("Prodline").display(60, 800).foregroundStyle(Theme.ink)
            Text("Ship a project every cycle, watch its numbers come in, and keep the streak going.")
                .font(.ui(19)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct SampleCard { let name: String; let cover: UIImage?; let accent: Accent; let day: Int; let phase: String }
    /// The demo projects' photos, colored the same way a real cover would be.
    private static let sampleCards: [SampleCard] = [("Habit Hero", 12, "Building"), ("Pixel Quest", 5, "Building"), ("Side Shop", 9, "Observing")]
        .map { name, day, phase in
            let spec = DemoData.projects.first { $0.name == name }
            let cover = spec?.cover
            let hex = cover.flatMap(ImageTools.dominantAccentHex) ?? spec?.accent ?? 0x1C1C1E
            return SampleCard(name: name, cover: cover, accent: Accent(hex: hex), day: day, phase: phase)
        }

    private var scheme: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your rhythm").eyebrow()
                Text("How do you like to build?").display(34, 750).foregroundStyle(Theme.ink)
            }
            SchemeEditor(profile: profile).card()
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stay on time").eyebrow()
                Text("A nudge on deadline days").display(34, 750).foregroundStyle(Theme.ink)
            }
            // Notification preview.
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x58CC02))
                    .frame(width: 38, height: 38)
                    .overlay(Text("H").display(20, 800).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Habit Hero: deadline day").font(.ui(15, .semibold))
                        Spacer()
                        Text("9:00").font(.ui(13)).foregroundStyle(Theme.secondary)
                    }
                    Text("Checkpoint 2 is due today. You've got this.").font(.ui(15)).foregroundStyle(Theme.inkSoft)
                }
            }
            .card(padding: 14, radius: 22)
            Text("We remind you in the morning and again at 6 pm if it's still open. Nothing else.")
                .font(.ui(17)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func next() {
        if step < 2 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        } else {
            Task { profile.remindersEnabled = await Notifier.requestAuth(); finish() }
        }
    }

    private func finish() {
        profile.onboarded = true
        try? context.save()
        celebration.fire(title: "You're set", subtitle: "Create your first project to begin.")
    }
}
