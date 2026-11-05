import SwiftUI
import SwiftData

/// Six short steps: basics → look (card + color) → stages → connections → checkpoints → overview, which
/// starts the project or saves it as a draft (no start date). A draft opens here again, on the overview.
struct CreateProjectFlow: View {
    let profile: Profile
    /// Started from the idea inbox: name and pitch come prefilled.
    var idea: Idea? = nil
    /// A draft to finish planning or start.
    var editing: Project? = nil
    var onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Environment(\.wideLayout) private var wide
    @Query private var projects: [Project]

    @State private var step = 0
    @State private var name = ""
    @State private var details = ""
    @State private var imageData: Data?
    @State private var photoHex: Int?
    @State private var lockedToPhoto = false
    @State private var accentHex = Theme.swatches[0]
    @State private var startDate = Date.now.startOfDay
    @State private var stages: [Stage] = []
    /// The checkpoints as planned, per stage.
    @State private var plan: [PlannedCheckpoint] = []
    /// The stages the plan was last laid out for (ids and lengths), to fit it again when they change.
    @State private var planFor: [Stage] = []
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var probe: ProbeState = .idle
    @State private var repo = ""
    @State private var token = ""
    @State private var repoCheck: RepoCheck = .idle
    @State private var repoPreview: GoalEngine.RepoPreview?
    @State private var loadingRepo = false
    @State private var drafting = false
    @State private var draftNote: String?
    @FocusState private var focus: Field?
    private enum Field { case name, details }

    private let steps = 6
    private var accent: Accent { Accent(hex: accentHex) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group {
            if wide { wideBody } else { phoneBody }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, accent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(!trimmedName.isEmpty)
        .onAppear {
            stages = profile.newStages
            startDate = max(ScheduleEngine.nextProjectDate(projects: projects, profile: profile), .now.startOfDay)
            let used = Set(projects.map(\.accentHex))
            accentHex = Theme.swatches.first { !used.contains($0) } ?? Theme.swatches[projects.count % Theme.swatches.count]
            focus = .name
            if let idea {
                name = idea.title
                details = idea.note
                startDate = .now.startOfDay
            }
            if let editing { load(editing) }
            fitPlan()
            #if DEBUG
            let jump = UserDefaults.standard.integer(forKey: "PRODLINE_CREATE_STEP")
            if jump > 0 { name = "Kite"; details = "A kite-surf spot finder."; step = min(jump, steps - 1); focus = nil }
            #endif
        }
    }

    // MARK: Wide (Mac)

    /// The project as it takes shape on the left (the card you're making, editable on the look step),
    /// the step on the right.
    private var wideBody: some View {
        HStack(spacing: 0) {
            ZStack {
                Theme.card
                AccentGlow(accent: accent)
                VStack(spacing: 22) {
                    if step == 1 {
                        CardCoverEditor(name: trimmedName.isEmpty ? "Your project" : trimmedName, imageData: $imageData,
                                        accentHex: $accentHex, photoHex: $photoHex, lockedToPhoto: $lockedToPhoto,
                                        footnote: firstStageNote)
                            .frame(width: 250)
                    } else {
                        ProjectCardFace(name: trimmedName.isEmpty ? "Your project" : trimmedName,
                                        initial: trimmedName.first.map { String($0).uppercased() } ?? "?",
                                        accent: accent, cover: imageData.flatMap { UIImage(data: $0) },
                                        cornerLabel: "Starts", cornerValue: startDate.formatted(.dateTime.day()),
                                        footnote: firstStageNote)
                            .frame(width: 250, height: 350)
                            .shadow(color: .black.opacity(0.2), radius: 22, y: 12)
                    }
                    Text(step == 1 ? "Drop in a photo or keep the color." : startDate == .now.startOfDay ? "Starts today" : "Starts \(startDate.shortDay)")
                        .font(.ui(13, .medium)).foregroundStyle(Theme.secondary)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
            }
            .frame(width: 380)
            .clipped()

            VStack(spacing: 0) {
                topBar
                MacScroll {
                    Group {
                        switch step {
                        case 0: basicsStep
                        case 1: lookStep
                        case 2: stagesStep
                        case 3: connectStep
                        case 4: goalsStep
                        default: overviewStep
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 20)
                }
                VStack(spacing: 6) { bottomBar }
                    .padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var phoneBody: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case 0: basicsStep
                    case 1: lookStep
                    case 2: stagesStep
                    case 3: connectStep
                    case 4: goalsStep
                    default: overviewStep
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
            // Once it has a face, the project rides along in the corner (wide: it's on the left already).
            if step >= 2 && !wide {
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
        if step == steps - 1 {
            Button(startDate <= .now.startOfDay ? "Start today" : "Start on \(startDate.shortDay)") { create(asDraft: false) }
                .buttonStyle(.chunky)
            Button("Save as draft") { create(asDraft: true) }
                .buttonStyle(.chunky(.neutral, height: 50))
        } else {
            Button("Continue", action: next)
                .buttonStyle(.chunky)
                .disabled(!canContinue)
            if step == 3 && endpoint.isEmpty {
                BarFootnote("No endpoint yet? You'll see sample data until you connect.")
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: !trimmedName.isEmpty
        case 2: !stages.isEmpty && stages.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        default: true
        }
    }

    private var firstStageNote: String {
        guard let first = stages.first else { return "" }
        return "\(first.name.isEmpty ? "Stage 1" : first.name) · \(first.days)d"
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
            stepTitle("Step 1 of 6", "What are you building?")

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
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 2))
            .opacity(0.55)
            .allowsHitTesting(false)
            .accessibilityLabel("Collaborators, coming soon")
        }
    }

    private var lookStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle("Step 2 of 6", "Give it a face")
            if !wide {
                CardCoverEditor(name: trimmedName, imageData: $imageData, accentHex: $accentHex,
                                photoHex: $photoHex, lockedToPhoto: $lockedToPhoto,
                                footnote: firstStageNote)
                    .frame(width: 236)
                    .frame(maxWidth: .infinity)
            }
            AccentSlider(accentHex: $accentHex, locked: $lockedToPhoto, photoHex: photoHex)
        }
    }

    private var stagesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 3 of 6", "Plan the stages")
            Text("Split the project into stretches, as broad or as fine as you like: a build and a launch, or research, prototype, beta, launch week. You move on to the next stage once everything in this one is done.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Starts").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("", selection: $startDate, in: Date.now.startOfDay..., displayedComponents: .date)
                    .labelsHidden().tint(accent.base)
            }
            .card(padding: 16, radius: 22)
            StageListEditor(stages: $stages, start: startDate)
            if !stages.isEmpty {
                StageTimelineBar(spans: Project.previewSpans(stages, start: startDate), today: startDate.adding(days: -1))
                    .padding(.horizontal, 4)
                Text("\(stages.map(\.days).reduce(0, +).durationText) in all, until \(startDate.adding(days: stages.map(\.days).reduce(0, +) - 1).shortDay)")
                    .font(.ui(13)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 4 of 6", "Connect your project")
            ConnectionFields(endpoint: $endpoint, apiKey: $apiKey, probe: $probe, repo: repo)
            Divider().padding(.vertical, 6)
            GitHubFields(repo: $repo, token: $token, check: $repoCheck)
        }
    }

    // MARK: Goals

    struct DraftGoal: Equatable { var title: String; var source: GoalSource }

    /// The plan in date order, with each checkpoint's date.
    private var deadlines: [(checkpoint: PlannedCheckpoint, date: Date)] {
        StageEngine.sorted(plan, stages: stages).map { ($0, StageEngine.date(of: $0, stages: stages, start: startDate)) }
    }

    private var githubSnapshot: GitHubSnapshot? {
        if case .ok(let snap) = repoCheck { return snap }
        return nil
    }

    /// prodline.json in the linked repo is the plan; suggestions only fill gaps when there's no file.
    private var repoHasPlan: Bool { repoPreview?.hasPlanFile ?? false }

    private var goalsStep: some View {
        let spans = Project.previewSpans(stages, start: startDate)
        let order = deadlines.map(\.checkpoint.id)
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 5 of 6", "Plan the checkpoints")

            if loadingRepo || drafting {
                HStack(spacing: 12) {
                    ProgressView().tint(accent.text)
                    Text(loadingRepo ? "Reading \(GitHubRepoRef(repo)?.slug ?? "your repo")…" : "Suggesting goals on your \(ThisDevice.name)…")
                        .font(.ui(15, .medium)).foregroundStyle(Theme.inkSoft)
                }
                .card()
            } else {
                Text(planIntro).font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(spans) { span in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(span.stage.name).display(20, 700).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(span.dateRange).font(.ui(13)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 4)
                        ForEach(deadlines.filter { $0.checkpoint.stageID == span.stage.id }, id: \.checkpoint.id) { d in
                            goalEditor(index: order.firstIndex(of: d.checkpoint.id) ?? 0, checkpoint: d.checkpoint, date: d.date, span: span)
                        }
                        Button {
                            Haptics.select()
                            withAnimation(.snappy) {
                                plan.append(PlannedCheckpoint(stageID: span.stage.id, day: max(0, span.stage.days / 2), title: "Checkpoint"))
                                plan = StageEngine.numbered(plan, stages: stages)
                            }
                        } label: {
                            Label("Add checkpoint to \(span.stage.name)", systemImage: "plus.circle")
                                .font(.ui(14, .semibold)).foregroundStyle(accent.text)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }
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

    private var overviewStep: some View {
        let spans = Project.previewSpans(stages, start: startDate)
        let counts = Dictionary(grouping: plan, by: \.stageID).mapValues(\.count)
        let goals = plan.map(\.goals.count).reduce(0, +)
        let total = stages.map(\.days).reduce(0, +)
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 6 of 6", "Ready to go?")
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    miniMark
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trimmedName).display(22, 750).foregroundStyle(Theme.ink)
                        if !details.isEmpty {
                            Text(details).font(.ui(14)).foregroundStyle(Theme.secondary).lineLimit(2)
                        }
                    }
                }
                StageTimelineBar(spans: spans, today: startDate.adding(days: -1))
                HStack {
                    overviewFigure("Starts", startDate <= .now.startOfDay ? "Today" : startDate.shortDay)
                    Spacer()
                    overviewFigure("Length", total.durationText)
                    Spacer()
                    overviewFigure("Checkpoints", "\(plan.count)")
                    Spacer()
                    overviewFigure("Goals", "\(goals)")
                }
            }
            .card()
            StageLegend(spans: spans, checkpoints: counts).card()
            if !repo.isEmpty || !endpoint.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let slug = GitHubRepoRef(repo)?.slug { Label(slug, systemImage: "chevron.left.forwardslash.chevron.right") }
                    if !endpoint.isEmpty { Label(endpoint, systemImage: "bolt.fill").lineLimit(1) }
                }
                .font(.ui(14, .medium)).foregroundStyle(Theme.inkSoft)
                .card()
            }
            Text("A draft keeps the plan without a start date: no deadlines, reminders or project slot until you start it from Dash.")
                .font(.ui(13)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func overviewFigure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(12, .medium)).foregroundStyle(Theme.secondary)
            Text(value).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
        }
    }

    private var planIntro: String {
        if repoHasPlan { return "Goals come from prodline.json in your repo and stay in sync with it. Rename checkpoints or add your own goals on top." }
        if repoPreview.map({ !$0.isEmpty }) ?? false {
            return GoalPlanner.isEnabled ? "GitHub issues fill their checkpoints; suggestions fill the rest. Edit freely." : "GitHub issues fill their checkpoints. Add your own goals to the rest."
        }
        if GoalPlanner.isEnabled { return "Suggested on your \(ThisDevice.name). Rename checkpoints and edit goals freely: each checkpoint completes once its goals are done." }
        return GoalPlanner.unavailableReason + " Name your checkpoints and add goals yourself, or leave them simple and tick them off."
    }

    private func planIndex(_ id: UUID) -> Int? { plan.firstIndex { $0.id == id } }

    private func goalEditor(index i: Int, checkpoint c: PlannedCheckpoint, date: Date, span: StageSpan) -> some View {
        let repoGoals = repoPreview?.goals[safe: i] ?? []
        let placeholder = (repoPreview?.names[safe: i] ?? nil) ?? c.title
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if c.isLaunch { Image(systemName: "flag.checkered").font(.system(size: 13)).foregroundStyle(accent.text) }
                TextField(placeholder, text: Binding(
                    get: { planIndex(c.id).map { plan[$0].titleIsCustom ? plan[$0].title : "" } ?? "" },
                    set: { new in
                        guard let k = planIndex(c.id) else { return }
                        let t = new.trimmingCharacters(in: .whitespaces)
                        plan[k].titleIsCustom = !t.isEmpty
                        plan[k].title = t.isEmpty ? "Checkpoint" : new
                        if t.isEmpty { plan = StageEngine.numbered(plan, stages: stages) }
                    }))
                    .font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    .submitLabel(.done)
                Spacer(minLength: 8)
                DatePicker("", selection: Binding(
                    get: { date },
                    set: { new in
                        guard let k = planIndex(c.id) else { return }
                        plan[k].day = min(max(0, Date.days(from: span.start, to: new)), span.stage.days - 1)
                        plan = StageEngine.numbered(plan, stages: stages)
                    }), in: span.start...span.plannedLastDay, displayedComponents: .date)
                    .labelsHidden().tint(accent.base)
                Button {
                    Haptics.soft()
                    withAnimation(.snappy) {
                        plan.removeAll { $0.id == c.id }
                        plan = StageEngine.numbered(plan, stages: stages)
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
            ForEach(repoGoals.indices, id: \.self) { j in
                HStack(spacing: 10) {
                    Image(systemName: repoGoals[j].source.symbol).font(.system(size: 12)).foregroundStyle(accent.text)
                    Text(repoGoals[j].title).font(.ui(15)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                .accessibilityHint(repoGoals[j].source.label)
            }
            ForEach(c.goals.indices, id: \.self) { j in
                HStack(spacing: 10) {
                    Image(systemName: c.goals[j].sourceRaw == GoalSource.ai.rawValue ? "sparkles" : "circle")
                        .font(.system(size: 12)).foregroundStyle(accent.text)
                    TextField("Goal", text: Binding(
                        get: { planIndex(c.id).flatMap { plan[$0].goals[safe: j]?.title } ?? "" },
                        set: { if let k = planIndex(c.id), plan[k].goals.indices.contains(j) { plan[k].goals[j].title = $0 } }))
                        .font(.ui(15))
                    Button {
                        Haptics.soft()
                        withAnimation(.snappy) { if let k = planIndex(c.id), plan[k].goals.indices.contains(j) { plan[k].goals.remove(at: j) } }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                withAnimation(.snappy) { if let k = planIndex(c.id) { plan[k].goals.append(PlannedGoal(title: "", sourceRaw: GoalSource.manual.rawValue)) } }
            } label: {
                Label("Add goal", systemImage: "plus").font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
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

    /// Lays the checkpoints out for the stages: the defaults for a new plan, and after a stage change the
    /// same checkpoints (days clamped into their stage) plus defaults for stages that have none.
    private func fitPlan() {
        guard planFor != stages else { return }
        let ids = Set(stages.map(\.id))
        var kept = plan.filter { ids.contains($0.stageID) }
        for k in kept.indices {
            if let s = stages.first(where: { $0.id == kept[k].stageID }) { kept[k].day = min(kept[k].day, max(0, s.days - 1)) }
        }
        let fresh = StageEngine.defaultCheckpoints(stages: stages, start: startDate, weekdayMask: profile.milestoneWeekdayMask)
        let covered = Set(kept.map(\.stageID))
        plan = StageEngine.numbered(kept + fresh.filter { !covered.contains($0.stageID) }, stages: stages)
        planFor = stages
    }

    /// Repo first (prodline.json, then issues), suggestions only where the repo leaves a checkpoint empty.
    private func draft(force: Bool) async {
        fitPlan()
        let ms = deadlines
        if !force && repoPreview != nil { return }
        // Keep what the user typed; only replace earlier suggestions.
        for k in plan.indices { plan[k].goals.removeAll { $0.sourceRaw == GoalSource.ai.rawValue } }

        if let ref = GitHubRepoRef(repo) {
            var snap = githubSnapshot
            if snap == nil {
                loadingRepo = true
                snap = try? await GitHubClient(repo: ref, token: token.isEmpty ? nil : token, base: GitHubService.base(for: ref)).fetch()
                loadingRepo = false
                if let snap { repoCheck = .ok(snap) }
            }
            if let snap { repoPreview = GoalEngine.repoPreview(snap, dues: ms.map(\.date), start: startDate) }
            else { draftNote = "Couldn't read the repo right now. Its goals will sync in once the project is created." }
        } else {
            repoPreview = nil
        }

        guard GoalPlanner.isEnabled, !repoHasPlan else { return }
        let empty = Set(ms.indices.filter { (repoPreview?.goals[safe: $0] ?? []).isEmpty && ms[$0].checkpoint.goals.isEmpty })
        guard !empty.isEmpty else { return }
        drafting = true
        defer { drafting = false }
        do {
            let working = stages.filter { !$0.decides }.map(\.days).reduce(0, +)
            let result = try await GoalPlanner.draft(name: trimmedName, details: details, buildDays: max(1, working),
                                                     deadlines: ms.map { .init(title: $0.checkpoint.title, date: $0.date) },
                                                     github: githubSnapshot)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                for (n, titles) in result where empty.contains(n - 1) {
                    guard let k = planIndex(ms[n - 1].checkpoint.id) else { continue }
                    plan[k].goals += titles.map { PlannedGoal(title: $0, sourceRaw: GoalSource.ai.rawValue) }
                }
            }
            draftNote = nil
            Haptics.success()
        } catch {
            draftNote = "Couldn't suggest goals right now. You can add them later from the project."
        }
    }

    // MARK: Actions

    private func next() {
        guard canContinue else { return }
        focus = nil
        if step == 2 {
            for i in stages.indices { stages[i].name = stages[i].name.trimmingCharacters(in: .whitespaces) }
            fitPlan()
        }
        if step < steps - 1 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        }
    }

    /// A draft opens on the overview with everything as it was saved.
    private func load(_ p: Project) {
        name = p.name
        details = p.details
        imageData = p.coverImage
        accentHex = p.accentHex
        lockedToPhoto = p.coverImage != nil
        endpoint = p.endpoint
        apiKey = Keychain.get(p.id.uuidString) ?? ""
        repo = p.githubRepo
        token = Keychain.get("gh-" + p.id.uuidString) ?? ""
        stages = p.stages
        plan = p.plannedCheckpoints
        planFor = stages
        startDate = max(.now.startOfDay, ScheduleEngine.nextProjectDate(projects: projects.filter { $0.id != p.id }, profile: profile))
        step = steps - 1
        focus = nil
    }

    private func create(asDraft: Bool) {
        fitPlan()
        let p = editing ?? Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                                 buildDays: profile.buildDays, observeDays: profile.observeDays)
        p.name = trimmedName
        p.accentHex = accentHex
        p.startDate = startDate.startOfDay
        p.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        p.coverImage = imageData
        if p.criteria.isEmpty { p.criteria = profile.defaultCriteria }
        p.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: p.id.uuidString)
        p.githubRepo = GitHubRepoRef(repo)?.slug ?? ""
        Keychain.set(token.trimmingCharacters(in: .whitespaces), for: "gh-" + p.id.uuidString)
        p.stages = stages.map { Stage(id: $0.id, name: $0.name, days: $0.days, decides: $0.decides) }
        p.plannedCheckpoints = StageEngine.numbered(plan.map { c in
            var c = c
            c.goals = c.goals.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return c
        }, stages: stages)
        p.isDraft = asDraft
        if editing == nil {
            ScheduleEngine.createProject(p, profile: profile, context: context)
        } else if !asDraft {
            StageEngine.start(p, on: startDate, profile: profile, context: context)
        }
        if !asDraft, let snap = githubSnapshot { GoalEngine.syncGitHub(snap, project: p, context: context) }
        try? context.save()
        if !asDraft && profile.remindersEnabled { Task { _ = await Notifier.requestAuth() } }
        if let idea {
            idea.startedAt = .now
            idea.projectID = p.id
            try? context.save()
        }
        if asDraft {
            celebration.fire(title: "Saved as a draft", subtitle: "Start \(p.name) from Dash when you're ready.", accent: p.accent, confetti: false)
        } else {
            let first = p.stages.first.map { "First up: \($0.name), \($0.days.durationText)." } ?? ""
            celebration.fire(title: "\(p.name) is live", subtitle: first, accent: p.accent)
        }
        onCreated(p.id)
        dismiss()
    }
}
