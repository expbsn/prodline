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
    @State private var finder = MockServerFinder()
    @State private var demoVisible = false
    @Environment(\.isActiveTab) private var isActiveTab
    /// Widget previews use your projects; without any, the sample ones.
    private var widgetData: WidgetData {
        for p in projects { WidgetCovers.overrides[p.id.uuidString] = p.cover }
        return projects.isEmpty ? .sample()
            : WidgetData(generatedAt: .now, streak: profile.streak,
                         projects: projects.map { WidgetPublisher.make($0, refresher: refresher, now: .now) })
    }
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    @AppStorage(AppSettings.Key.refreshSeconds) private var refreshSeconds = 30
    @AppStorage(AppSettings.Key.githubMinutes) private var githubMinutes = 10
    @AppStorage(AppSettings.Key.commitWatch) private var commitWatch = true
    @AppStorage(AppSettings.Key.suggestions) private var suggestions = true
    @AppStorage(AppSettings.Key.sampleData) private var sampleData = true
    @AppStorage(AppSettings.Key.haptics) private var haptics = true
    @AppStorage(AppSettings.Key.relayURL) private var relayURL = ""
    @AppStorage(LiveActivities.enabledKey) private var liveActivity = true
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
                        Text("Best streak \(profile.bestStreak) day\(profile.bestStreak == 1 ? "" : "s")").font(.ui(13)).foregroundStyle(Theme.secondary)
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("When you work").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                            HStack(spacing: 6) {
                                ForEach(WorkStyle.allCases) { w in
                                    Chip(title: w.title.components(separatedBy: " ").last ?? w.title, isOn: profile.workStyle == w) {
                                        profile.apply(w)
                                        Notifier.rescheduleAll(projects: projects, profile: profile)
                                    }
                                }
                            }
                        }
                        HourPicker(title: "Deadline reminder", hour: $profile.reminderHour)
                            .onChange(of: profile.reminderHour) { Notifier.rescheduleAll(projects: projects, profile: profile) }
                        HourPicker(title: "Last call", hour: $profile.nudgeHour)
                            .onChange(of: profile.nudgeHour) { Notifier.rescheduleAll(projects: projects, profile: profile) }
                    }
                }
                .card()
                .padding(.horizontal, 16)

                WidgetsCard(data: widgetData).padding(.horizontal, 16)

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
            optionRow("Builds at once", "Projects in the build phase at the same time. Past the limit, new ideas go to the idea inbox.") {
                HStack(spacing: 6) {
                    ForEach(ProjectLimit.choices, id: \.self) { v in
                        Chip(title: ProjectLimit.label(v), isOn: profile.buildLimit == v) {
                            profile.buildLimit = v
                            try? context.save()
                        }
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
            optionRow("Relay for instant updates", "Your deployed relay (relay/ in the repo). Pushes to linked repos then sync within seconds.") {
                TextField("https://prodline-relay.you.workers.dev", text: $relayURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(.ui(15))
                    .inputField()
                    .onSubmit {
                        guard AppSettings.relayURL != nil else { return }
                        UIApplication.shared.registerForRemoteNotifications()
                    }
            }
            toggleRow("Deadline Live Activity", "On the Lock Screen and in the Dynamic Island when a checkpoint is due today and still has open goals.", $liveActivity)
                .onChange(of: liveActivity) { Task { await LiveActivities.sync(projects) } }
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
            celebration.fire(title: "+$49 sale", subtitle: "Simulated on \(p.name)", accent: .sale)
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
        UserDefaults.standard.removeObject(forKey: "githubAPIBase")
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
            Text("Run `python3 MockProject/server.py --host 0.0.0.0` on your Mac, on the same Wi-Fi as this phone. The address fills in by itself once the server is found.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Mock server URL", text: $mockServerURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .inputField()
            HStack(spacing: 8) {
                if let found = finder.url {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    Text(found == mockServerURL ? "Found the server on your Mac" : "Found \(found)")
                    if found != mockServerURL { Button("Use") { mockServerURL = found }.fontWeight(.semibold) }
                } else if !isSimulator && mockServerURL.contains("127.0.0.1") {
                    ProgressView().controlSize(.small)
                    Text("Looking for the server on your network… 127.0.0.1 is this phone, not your Mac.")
                } else {
                    ProgressView().controlSize(.small)
                    Text("Looking for the server on your network…")
                }
                Spacer(minLength: 0)
            }
            .font(.ui(13)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button("Load demo projects") {
                DemoData.load(baseURL: mockServerURL, profile: profile, context: context)
                celebration.fire(title: "Demo loaded", subtitle: "\(DemoData.projects.count) projects connected to \(URL(string: mockServerURL)?.host ?? "the mock server")")
                Task {
                    let fresh = (try? context.fetch(FetchDescriptor<Project>())) ?? []
                    await refresher.refresh(projects: fresh, context: context, force: true)
                }
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
                    celebration.nudge(title: "A deadline slipped", subtitle: "Finish it today. Late still earns XP.")
                }
                devButton("Play the streak flame", "flame.fill") {
                    celebration.fire(title: "+3 XP", subtitle: "A goal, for the demo", accent: Accent(hex: 0x58CC02), confetti: false)
                    celebration.lightStreak(max(1, profile.streak))
                }
                devButton("Play the ship animation", "paperplane.fill") {
                    let p = projects.first { $0.phase() == .building } ?? projects.first
                    celebration.celebrateShip(.init(daysEarly: 5, plannedDays: 14, project: p?.name ?? "Habit Hero",
                                                    accent: p?.accent ?? Accent(hex: 0x58CC02), xp: 70))
                }
                devButton("Play weekly wrap", "play.rectangle.fill") {
                    NotificationCenter.default.post(name: WeeklyReview.open, object: nil)
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
        // Only search while this card is actually on screen, so the local network prompt shows up in context.
        .onScrollVisibilityChange(threshold: 0.1) { demoVisible = $0 }
        .onChange(of: isActiveTab && demoVisible, initial: true) { _, on in on ? finder.start() : finder.stop() }
        .onChange(of: finder.url) { _, found in
            // On a phone, 127.0.0.1 can never work: take the discovered address.
            if let found, !isSimulator, mockServerURL.contains("127.0.0.1") { mockServerURL = found }
        }
    }
}

struct OnboardingView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Environment(DataRefresher.self) private var refresher
    /// 0 story, 1 first project, 2 what counts as a win, 3 integrations, 4 work hours + reminders, 5 rhythm.
    @State private var step = 0
    @State private var name = ""
    @State private var imageData: Data?
    @State private var photoHex: Int?
    @State private var lockedToPhoto = false
    @State private var accentHex = Theme.swatches[0]
    @State private var skippedProject = false
    /// The first project while onboarding runs: integrations attach to it before it's created at the end.
    @State private var draft: Project?
    @State private var editing: Integration?
    @FocusState private var nameFocused: Bool

    /// 1 project, 2 win, 3 integrations (only with a project), 4 work hours, 5 rhythm.
    private let lastStep = 5
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        if step == 0 {
            // Selling the idea: the scroll story. The setup steps follow.
            StoryOnboarding { next() }
                .transition(.opacity)
        } else {
            setup
        }
    }

    private var setup: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if step > 1 {
                Button {
                    Haptics.soft()
                    nameFocused = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        step -= (step == 4 && skippedProject) ? 2 : 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.secondary)
                        .frame(width: 36, height: 36)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ChunkyProgressBar(value: Double(step) / Double(lastStep), color: Theme.ink, height: 12)
            }
            .padding(.horizontal, 20).padding(.top, 14)
            .frame(height: 50)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step > 1)

            ScrollView(showsIndicators: false) {
                Group {
                    switch step {
                    case 1: firstProject
                    case 2: success
                    case 3: integrations
                    case 4: workHours
                    default: scheme
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar { bottomBar }
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $editing) { i in
            if let draft {
                IntegrationEditor(project: draft, integration: i, isNew: !draft.integrations.contains { $0.id == i.id }, live: false)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch step {
        case 1:
            Button("Continue") { skippedProject = false; next() }
                .buttonStyle(.chunky)
                .disabled(trimmedName.isEmpty)
            secondary("I'll do it later") { skippedProject = true; next() }
        case 2:
            Button("Continue", action: next)
                .buttonStyle(.chunky)
                .disabled(profile.successFocus == nil)
        case 3:
            Button("Continue", action: next)
                .buttonStyle(.chunky)
            if (draft?.integrations ?? []).isEmpty {
                secondary("I'll connect them later", next)
            }
        case 4:
            Button("Turn on reminders") {
                Task { profile.remindersEnabled = await Notifier.requestAuth(); next() }
            }
            .buttonStyle(.chunky)
            .disabled(profile.workStyle == nil)
            secondary("Not now") { profile.remindersEnabled = false; next() }
                .disabled(profile.workStyle == nil)
        case lastStep:
            Button("Let's go", action: next)
                .buttonStyle(.chunky)
        default:
            Button("Continue", action: next)
                .buttonStyle(.chunky)
        }
    }

    private func secondary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.ui(15, .semibold)).foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
    }

    private func header(_ eyebrow: String, _ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).eyebrow()
            Text(title).display(34, 750).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub).font(.ui(17)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Steps

    private var firstProject: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Your first project", "What are you building?",
                   "Name it and give it a face. You can change all of it later, nobody's grading this.")
            TextField("", text: $name, prompt: Text("e.g. Side Shop").foregroundStyle(Theme.tertiary))
                .focused($nameFocused)
                .submitLabel(.done)
                .inputField(focused: nameFocused)
            AccentSlider(accentHex: $accentHex, locked: $lockedToPhoto, photoHex: photoHex)
            CardCoverEditor(name: trimmedName.isEmpty ? "Your project" : trimmedName, imageData: $imageData,
                            accentHex: $accentHex, photoHex: $photoHex, lockedToPhoto: $lockedToPhoto,
                            footnote: "Building · \(profile.buildDays)d")
                .frame(width: 210)
                .frame(maxWidth: .infinity)
        }
        .environment(\.accent, Accent(hex: accentHex))
    }

    private var success: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Your finish line", "How will you know it worked?",
                   "Pick what counts as a win. It's what Prodline checks when it's time to keep, pivot or kill.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(SuccessFocus.allCases) { f in
                    focusTile(f)
                }
            }
            if let f = profile.successFocus, !f.presets.isEmpty, let key = f.key {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Call it a win at").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        ForEach(f.presets, id: \.self) { v in
                            let n = Int(v).formatted()
                            Chip(title: key == MetricKey.revenue.rawValue ? "$" + n : n,
                                 isOn: profile.successTarget == v) { profile.successTarget = v }
                        }
                        if key != MetricKey.revenue.rawValue {
                            Text(VerdictEngine.title(key).lowercased()).font(.ui(15, .semibold)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Text("Counted over the observe phase. Change it per project anytime.")
                        .font(.ui(14)).foregroundStyle(Theme.secondary)
                }
                .environment(\.accent, Accent(hex: f.hex))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: profile.successFocusRaw)
    }

    private func focusTile(_ f: SuccessFocus) -> some View {
        choiceTile(title: f.title, blurb: f.blurb, symbol: f.symbol, hex: f.hex, on: profile.successFocus == f) {
            profile.successFocus = f
            profile.successTarget = f.defaultTarget
        }
    }

    /// A big chunky choice: icon, title and a line, with a colored edge when picked.
    private func choiceTile(title: String, blurb: String, symbol: String, hex: Int, on: Bool, pick: @escaping () -> Void) -> some View {
        let a = Accent(hex: hex)
        return Button {
            Haptics.select()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { pick() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                    .foregroundStyle(on ? a.on : a.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(on ? a.base : a.tint))
                Text(title).font(.display(18, 750)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(blurb).font(.ui(13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on ? a.dark : Theme.line).offset(y: on ? 3 : 6)
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
                    RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(on ? a.base : .clear, lineWidth: 2.5)
                }
            }
            .offset(y: on ? 3 : 0)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Integrations

    /// Only services whose official logo we're allowed to show (design/IMAGE_CREDITS.md), the ones that
    /// fit the picked win first. The rest are in the project settings.
    private var onboardingKinds: [IntegrationKind] {
        // Vercel keeps its generic triangle (its real logo needs written permission), but deploys matter.
        let withLogo = IntegrationKind.allCases.filter { $0.logo != nil } + [.vercel]
        let first: [IntegrationKind] = switch profile.successFocus {
        case .money: [.stripe, .revenueCat]
        case .users: [.revenueCat, .stripe]
        case .audience: [.youtube, .bluesky]
        case .ship, nil: [.vercel]
        }
        return first.filter(withLogo.contains) + withLogo.filter { !first.contains($0) }
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Your numbers", "Plug in your numbers",
                   "Revenue, visitors, downloads: straight from the tools you already use. No spreadsheets, no copy-paste.")
            integrationList("Connect now", onboardingKinds)
            Text("Lots more in the project settings later: App Store Connect, Shopify, Plausible, Netlify, npm and others.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func integrationList(_ title: String, _ kinds: [IntegrationKind]) -> some View {
        let connected = Set((draft?.integrations ?? []).map(\.kind))
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow()
            VStack(spacing: 0) {
                ForEach(kinds) { kind in
                    Button {
                        Haptics.select()
                        if let existing = draft?.integrations.first(where: { $0.kind == kind }) {
                            editing = existing
                        } else {
                            editing = Integration(kind: kind)
                        }
                    } label: {
                        HStack(spacing: 0) {
                            IntegrationRow(kind: kind, caption: kind.provides)
                            if connected.contains(kind) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.success)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text("Connect").font(.ui(14, .semibold)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(Theme.background))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    if kind != kinds.last { Divider().padding(.leading, 52) }
                }
            }
            .card(padding: 14, radius: 20)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: connected)
        }
    }

    /// The project as typed so far; integrations attach to it before it's created.
    private func ensureDraft() {
        if draft == nil {
            draft = Project(name: trimmedName, accentHex: accentHex, startDate: .now.startOfDay,
                            buildDays: profile.buildDays, observeDays: profile.observeDays)
        }
        draft?.name = trimmedName
        draft?.accentHex = accentHex
    }

    private var scheme: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Your rhythm", "How do you like to build?",
                   "Sprinters, marathoners, weekend warriors: all welcome. Tweak it later if your life changes.")
            SchemeEditor(profile: profile).card()
        }
    }

    // MARK: Work hours

    private var workHours: some View {
        let shown = skippedProject || trimmedName.isEmpty ? "Side Shop" : trimmedName
        let style = profile.workStyle
        return VStack(alignment: .leading, spacing: 18) {
            header("Your hours", "When do you actually work on this?",
                   "Be honest. We won't tell your boss. Reminders and your weekly wrap show up when it suits you.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(WorkStyle.allCases) { w in
                    choiceTile(title: w.title, blurb: w.blurb, symbol: w.symbol, hex: w.hex, on: style == w) {
                        profile.apply(w)
                    }
                }
            }
            if style != nil {
                // Notification preview at the picked time, with your project when you made one.
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: skippedProject ? 0x3A3A3C : accentHex))
                        .frame(width: 38, height: 38)
                        .overlay(Text(String(shown.prefix(1)).uppercased()).display(20, 800).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(shown): deadline day").font(.ui(15, .semibold)).lineLimit(1)
                            Spacer()
                            Text(String(format: "%d:00", profile.reminderHour)).font(.ui(13)).foregroundStyle(Theme.secondary)
                                .contentTransition(.numericText())
                        }
                        Text("Checkpoint 1 is due today. You've got this.").font(.ui(15)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .card(padding: 14, radius: 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                HourPicker(title: "Pick an exact time", hour: $profile.reminderHour)
                Text("Deadline days at \(profile.reminderHour):00, a last call at \(profile.nudgeHour):00 if it's still open, "
                     + "and your weekly wrap on Sunday at \(WeeklyReview.hour):00. Nothing else, promise.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: profile.workStyleRaw)
        .animation(.snappy, value: profile.reminderHour)
    }

    // MARK: Flow

    private func next() {
        nameFocused = false
        if step < lastStep {
            // Without a project there's nothing to connect integrations to.
            let skip = step == 2 && skippedProject
            if step == 2 && !skip { ensureDraft() }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += skip ? 2 : 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        profile.onboarded = true
        if profile.remindersEnabled { WeeklyReview.scheduleNotification(enabled: true) }
        if !skippedProject && !trimmedName.isEmpty {
            let p = draft ?? Project(name: trimmedName, accentHex: accentHex, startDate: .now.startOfDay,
                                     buildDays: profile.buildDays, observeDays: profile.observeDays)
            // The rhythm may have changed after the draft was made.
            p.name = trimmedName
            p.accentHex = accentHex
            p.startDate = .now.startOfDay
            p.buildDays = profile.buildDays
            p.observeDays = profile.observeDays
            p.coverImage = imageData
            p.criteria = profile.defaultCriteria
            ScheduleEngine.createProject(p, profile: profile, context: context)
            try? context.save()
            if !p.integrations.isEmpty { Task { await refresher.refresh(projects: [p], context: context, force: true) } }
            celebration.fire(title: "\(p.name) is live", subtitle: "Build phase: \(profile.buildDays.durationText). Let's ship.", accent: p.accent)
        } else {
            try? context.save()
            celebration.fire(title: "You're set", subtitle: "Create your first project to begin.")
        }
    }
}

/// An hour from 5:00 to 23:00, as a menu.
struct HourPicker: View {
    let title: String
    @Binding var hour: Int

    var body: some View {
        HStack {
            Text(title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            Menu {
                Picker(title, selection: $hour) {
                    ForEach(5...23, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(String(format: "%02d:00", hour)).display(18, 700).contentTransition(.numericText())
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1.5))
            }
        }
    }
}
