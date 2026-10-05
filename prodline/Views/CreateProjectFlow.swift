import SwiftUI
import SwiftData

/// Five short steps: basics → look (card + color) → schedule → connections → goals.
struct CreateProjectFlow: View {
    let profile: Profile
    var onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]

    @State private var step = 0
    @State private var name = ""
    @State private var details = ""
    @State private var imageData: Data?
    @State private var photoHex: Int?
    @State private var lockedToPhoto = false
    @State private var accentHex = Theme.swatches[0]
    @State private var startDate = Date.now.startOfDay
    @State private var buildDays = 14
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var probe: ProbeState = .idle
    @State private var repo = ""
    @State private var token = ""
    @State private var repoCheck: RepoCheck = .idle
    /// Draft goals per deadline (index = position in the deadline list).
    @State private var draftGoals: [[DraftGoal]] = []
    /// Names typed for each deadline; empty keeps the automatic or repo-provided name.
    @State private var checkpointNames: [String] = []
    @State private var repoPreview: GoalEngine.RepoPreview?
    @State private var loadingRepo = false
    @State private var drafting = false
    @State private var draftNote: String?
    @FocusState private var focus: Field?
    private enum Field { case name, details }

    private let steps = 5
    private var accent: Accent { Accent(hex: accentHex) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case 0: basicsStep
                    case 1: lookStep
                    case 2: scheduleStep
                    case 3: connectStep
                    default: goalsStep
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar { bottomBar }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, accent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(!trimmedName.isEmpty)
        .onAppear {
            buildDays = profile.buildDays
            startDate = max(ScheduleEngine.nextProjectDate(projects: projects, profile: profile), .now.startOfDay)
            let used = Set(projects.map(\.accentHex))
            accentHex = Theme.swatches.first { !used.contains($0) } ?? Theme.swatches[projects.count % Theme.swatches.count]
            focus = .name
            #if DEBUG
            let jump = UserDefaults.standard.integer(forKey: "PRODLINE_CREATE_STEP")
            if jump > 0 { name = "Kite"; details = "A kite-surf spot finder."; step = min(jump, steps - 1); focus = nil }
            #endif
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.soft()
                if step == 0 { dismiss() } else { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step -= 1 } }
            } label: {
                Image(systemName: step == 0 ? "xmark" : "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 36, height: 36)
            }
            ChunkyProgressBar(value: Double(step + 1) / Double(steps), height: 14)
            // Once it has a face, the project rides along in the corner.
            if step >= 2 {
                miniMark.transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step)
    }

    private var miniMark: some View {
        Group {
            if let data = imageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(trimmedName.first.map { String($0).uppercased() } ?? "?")
                    .display(17, 800)
                    .foregroundStyle(accent.on)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(accent.base)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var bottomBar: some View {
        Button(step == steps - 1 ? "Create project" : "Continue", action: next)
            .buttonStyle(.chunky)
            .disabled(step == 0 && trimmedName.isEmpty)
        if step == 3 && endpoint.isEmpty {
            BarFootnote("No endpoint yet? You'll see sample data until you connect.")
        }
    }

    private func stepTitle(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).eyebrow(accent.text)
            Text(title).display(32, 750).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Steps

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle("Step 1 of 5", "What are you building?")

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").eyebrow()
                TextField("", text: $name, prompt: Text("e.g. Habit Hero").foregroundStyle(Theme.tertiary))
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .details }
                    .inputField(focused: focus == .name)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description").eyebrow()
                TextField("", text: $details,
                          prompt: Text("One or two lines on what it is and who it's for").foregroundStyle(Theme.tertiary),
                          axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focus, equals: .details)
                    .padding(.vertical, 14)
                    .inputField(focused: focus == .details)
            }

            collaborators
        }
    }

    private var collaborators: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Collaborators").eyebrow()
                Spacer()
                Text("Coming soon")
                    .font(.ui(11, .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.line))
            }
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ink).frame(width: 40, height: 40)
                    Text("You").font(.ui(12, .semibold)).foregroundStyle(.white)
                }
                Circle()
                    .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.tertiary))
                Text("Invite people to build with you")
                    .font(.ui(15)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 2))
            .opacity(0.55)
            .allowsHitTesting(false)
            .accessibilityLabel("Collaborators, coming soon")
        }
    }

    private var lookStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle("Step 2 of 5", "Give it a face")
            CardCoverEditor(name: trimmedName, imageData: $imageData, accentHex: $accentHex,
                            photoHex: $photoHex, lockedToPhoto: $lockedToPhoto,
                            footnote: "Building · \(buildDays)d")
                .frame(width: 236)
                .frame(maxWidth: .infinity)
            AccentSlider(accentHex: $accentHex, locked: $lockedToPhoto, photoHex: photoHex)
        }
    }

    private var scheduleStep: some View {
        let draft = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                            buildDays: buildDays, observeDays: profile.observeDays)
        let ms = ScheduleEngine.makeMilestones(for: draft, weekdayMask: profile.milestoneWeekdayMask)
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 3 of 5", "Set the clock")
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Starts").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden().tint(accent.base)
                }
                Divider()
                HStack {
                    Text("Build phase").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(buildDays.durationText).display(20, 700).foregroundStyle(accent.text)
                        .contentTransition(.numericText())
                }
                ChunkySlider(value: $buildDays, range: 3...42)
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("Your deadlines").eyebrow()
                ForEach(ms, id: \.id) { m in
                    HStack {
                        Image(systemName: m.isLaunch ? "flag.checkered" : (m.title == "Traction review" ? "chart.line.uptrend.xyaxis" : "checkmark.circle"))
                            .foregroundStyle(accent.text)
                            .frame(width: 22)
                        Text(m.title).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(m.dueDate.shortDay).font(.ui(14)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .card()
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 4 of 5", "Connect your project")
            ConnectionFields(endpoint: $endpoint, apiKey: $apiKey, probe: $probe)
            Divider().padding(.vertical, 6)
            GitHubFields(repo: $repo, token: $token, check: $repoCheck)
        }
    }

    // MARK: Goals

    struct DraftGoal: Equatable { var title: String; var source: GoalSource }

    private var deadlines: [Milestone] {
        let draft = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                            buildDays: buildDays, observeDays: profile.observeDays)
        return ScheduleEngine.makeMilestones(for: draft, weekdayMask: profile.milestoneWeekdayMask)
    }

    private var githubSnapshot: GitHubSnapshot? {
        if case .ok(let snap) = repoCheck { return snap }
        return nil
    }

    /// prodline.json in the linked repo is the plan; suggestions only fill gaps when there's no file.
    private var repoHasPlan: Bool { repoPreview?.hasPlanFile ?? false }

    private var goalsStep: some View {
        let ms = deadlines
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 5 of 5", "Plan the checkpoints")

            if loadingRepo || drafting {
                HStack(spacing: 12) {
                    ProgressView().tint(accent.text)
                    Text(loadingRepo ? "Reading \(GitHubRepoRef(repo)?.slug ?? "your repo")…" : "Suggesting goals on your iPhone…")
                        .font(.ui(15, .medium)).foregroundStyle(Theme.inkSoft)
                }
                .card()
            } else {
                Text(planIntro).font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(ms.enumerated()).dropLast(), id: \.offset) { i, m in
                    goalEditor(index: i, milestone: m)
                }
                if GoalPlanner.isEnabled && !repoHasPlan {
                    Button {
                        Task { await draft(force: true) }
                    } label: {
                        Label("Suggest again", systemImage: "arrow.clockwise")
                            .font(.ui(15, .semibold)).foregroundStyle(accent.text)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let note = draftNote {
                Text(note).font(.ui(13)).foregroundStyle(Theme.secondary)
            }
            GuideDisclosure(title: "How do goals work?") { GoalsGuideView() }
                .padding(.top, 4)
        }
        .task { await draft(force: false) }
    }

    private var planIntro: String {
        if repoHasPlan { return "Goals come from prodline.json in your repo and stay in sync with it. Rename checkpoints or add your own goals on top." }
        if repoPreview.map({ !$0.isEmpty }) ?? false {
            return GoalPlanner.isEnabled ? "GitHub issues fill their checkpoints; suggestions fill the rest. Edit freely." : "GitHub issues fill their checkpoints. Add your own goals to the rest."
        }
        if GoalPlanner.isEnabled { return "Suggested on your iPhone. Rename checkpoints and edit goals freely: each checkpoint completes once its goals are done." }
        return GoalPlanner.unavailableReason + " Name your checkpoints and add goals yourself, or leave them simple and tick them off."
    }

    private func goalEditor(index i: Int, milestone m: Milestone) -> some View {
        let repoGoals = repoPreview?.goals[safe: i] ?? []
        let placeholder = (repoPreview?.names[safe: i] ?? nil) ?? m.title
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(placeholder, text: Binding(
                    get: { checkpointNames[safe: i] ?? "" },
                    set: { if checkpointNames.indices.contains(i) { checkpointNames[i] = $0 } }))
                    .font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    .submitLabel(.done)
                Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                Spacer(minLength: 8)
                Text(m.dueDate.shortDay).font(.ui(13)).foregroundStyle(Theme.secondary)
            }
            ForEach(repoGoals.indices, id: \.self) { j in
                HStack(spacing: 10) {
                    Image(systemName: repoGoals[j].source.symbol).font(.system(size: 12)).foregroundStyle(accent.text)
                    Text(repoGoals[j].title).font(.ui(15)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                .accessibilityHint(repoGoals[j].source.label)
            }
            if draftGoals.indices.contains(i) {
                ForEach(draftGoals[i].indices, id: \.self) { j in
                    HStack(spacing: 10) {
                        Image(systemName: draftGoals[i][j].source == .ai ? "sparkles" : "circle")
                            .font(.system(size: 12)).foregroundStyle(accent.text)
                        TextField("Goal", text: Binding(
                            get: { draftGoals[safe: i]?[safe: j]?.title ?? "" },
                            set: { if draftGoals.indices.contains(i) && draftGoals[i].indices.contains(j) { draftGoals[i][j].title = $0 } }))
                            .font(.ui(15))
                        Button {
                            Haptics.soft()
                            withAnimation(.snappy) { _ = draftGoals[i].remove(at: j) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    withAnimation(.snappy) { draftGoals[i].append(DraftGoal(title: "", source: .manual)) }
                } label: {
                    Label("Add goal", systemImage: "plus").font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 16, radius: 22)
    }

    private func infoCard(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(accent.text)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.ui(14)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 16, radius: 22)
    }

    /// Repo first (prodline.json, then issues), suggestions only where the repo leaves a checkpoint empty.
    private func draft(force: Bool) async {
        let ms = deadlines
        if !force && draftGoals.count == ms.count { return }
        if checkpointNames.count != ms.count { checkpointNames = Array(repeating: "", count: ms.count) }
        // Keep what the user typed; only replace earlier suggestions.
        draftGoals = (0..<ms.count).map { i in (draftGoals[safe: i] ?? []).filter { $0.source != .ai } }

        if let ref = GitHubRepoRef(repo) {
            var snap = githubSnapshot
            if snap == nil {
                loadingRepo = true
                snap = try? await GitHubClient(repo: ref, token: token.isEmpty ? nil : token, base: GitHubService.base(for: ref)).fetch()
                loadingRepo = false
                if let snap { repoCheck = .ok(snap) }
            }
            if let snap { repoPreview = GoalEngine.repoPreview(snap, dues: ms.map(\.dueDate)) }
            else { draftNote = "Couldn't read the repo right now. Its goals will sync in once the project is created." }
        } else {
            repoPreview = nil
        }

        guard GoalPlanner.isEnabled, !repoHasPlan else { return }
        let empty = Set(ms.indices.filter { (repoPreview?.goals[safe: $0] ?? []).isEmpty })
        guard !empty.isEmpty else { return }
        drafting = true
        defer { drafting = false }
        do {
            let plan = try await GoalPlanner.draft(name: trimmedName, details: details, buildDays: buildDays,
                                                   deadlines: ms.enumerated().map { i, m in
                                                       .init(title: name(at: i, default: m.title), date: m.dueDate)
                                                   },
                                                   github: githubSnapshot)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                for (n, titles) in plan where empty.contains(n - 1) {
                    draftGoals[n - 1] += titles.map { DraftGoal(title: $0, source: .ai) }
                }
            }
            draftNote = nil
            Haptics.success()
        } catch {
            draftNote = "Couldn't suggest goals right now. You can add them later from the project."
        }
    }

    /// Typed name, else the repo's name, else the automatic one.
    private func name(at i: Int, default fallback: String) -> String {
        let typed = (checkpointNames[safe: i] ?? "").trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        return (repoPreview?.names[safe: i] ?? nil) ?? fallback
    }

    // MARK: Actions

    private func next() {
        guard !(step == 0 && trimmedName.isEmpty) else { return }
        focus = nil
        if step < steps - 1 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        } else {
            create()
        }
    }

    private func create() {
        let p = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                        buildDays: buildDays, observeDays: profile.observeDays)
        p.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        p.coverImage = imageData
        p.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: p.id.uuidString)
        p.githubRepo = GitHubRepoRef(repo)?.slug ?? ""
        Keychain.set(token.trimmingCharacters(in: .whitespaces), for: "gh-" + p.id.uuidString)
        ScheduleEngine.createProject(p, profile: profile, context: context)
        let ms = p.sortedMilestones
        for (i, name) in checkpointNames.enumerated() where ms.indices.contains(i) && !name.trimmingCharacters(in: .whitespaces).isEmpty {
            ScheduleEngine.rename(ms[i], to: name)
        }
        // Your goals and suggestions first, then the repo (whose plan replaces suggestions).
        for (i, goals) in draftGoals.enumerated() where ms.indices.contains(i) {
            for source in [GoalSource.ai, .manual] {
                GoalEngine.addGoals(goals.filter { $0.source == source }.map(\.title), source: source, to: ms[i], context: context)
            }
        }
        if let snap = githubSnapshot { GoalEngine.syncGitHub(snap, project: p, context: context) }
        try? context.save()
        if profile.remindersEnabled { for m in ms { Notifier.schedule(m, hour: profile.reminderHour) } }
        if profile.remindersEnabled { Task { _ = await Notifier.requestAuth() } }
        celebration.fire(title: "\(p.name) is live", subtitle: "Build phase: \(buildDays.durationText). Let's ship.", accent: p.accent)
        onCreated(p.id)
        dismiss()
    }
}
