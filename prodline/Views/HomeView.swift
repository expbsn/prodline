import SwiftUI
import SwiftData

/// Shared geometry for the Dash card, so the project page can mirror it exactly.
enum DashLayout {
    /// Eyebrow + title + spacing above the carousel.
    static let header: CGFloat = 122
    /// Header → top of the card.
    static let cardTop: CGFloat = 34
    /// Card bottom → page dots. The floor shadow lives in this gap.
    static let shadowGap: CGFloat = 46
    /// Dots, summary, meta row and the button below them.
    static let panel: CGFloat = 185

    /// As large as the screen allows while the panel's button stays above the tab bar.
    static func cardWidth(in size: CGSize) -> CGFloat {
        let byHeight = (size.height - header - shadowGap - panel) * 5 / 7
        return max(170, min(size.width * 0.66, byHeight, 320))
    }

    /// Last on-screen frame of the focused Dash card; used when a project opens from elsewhere.
    static var lastCardFrame: CGRect?
}

/// Projects as playing cards in a horizontal 3D carousel; the focused card drives the panel below.
struct HomeView: View {
    let profile: Profile
    @Binding var focusedID: UUID?
    let zoom: Namespace.ID
    var onOpen: (Project, CGRect?) -> Void
    var onCreate: () -> Void
    var onStreak: () -> Void
    var onReview: () -> Void = {}

    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher
    @Environment(\.modelContext) private var context
    /// On-screen frames of the cards, so the project page can put its card exactly there.
    @State private var cardFrames: [UUID: CGRect] = [:]
    /// The review counts as seen the moment it opens; reading it here makes the chip go away right then.
    @AppStorage(WeeklyReview.watchedKey) private var watchedWeek = ""
    /// Once the user touches the carousel, startup centering stands down so it can't fight the swipe.
    @State private var userScrolled = false

    static let createID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    private let spacing: CGFloat = 16

    private var focused: Project? { projects.first { $0.id == focusedID } }
    private var accent: Accent { focused?.accent ?? .neutral }
    private var ids: [UUID] { projects.map(\.id) + [Self.createID] }

    var body: some View {
        GeometryReader { geo in
            let cardW = DashLayout.cardWidth(in: geo.size)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(eyebrow: "Prodline", title: "Projects") {
                        HStack(alignment: .top, spacing: 10) {
                            if reviewWaiting { reviewChip.transition(.scale.combined(with: .opacity)) }
                            streakBadge
                        }
                    }

                    carousel(cardW: cardW, screenW: geo.size.width)
                        .padding(.top, DashLayout.cardTop)

                    dots.frame(maxWidth: .infinity).padding(.top, DashLayout.shadowGap)

                    infoPanel
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .environment(\.accent, accent)
                        .id(focusedID)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .padding(.bottom, 24)
            }
            .refreshable { await refresher.refresh(projects: projects, context: context, force: true) }
        }
        .background(alignment: .top) {
            // Soft wash of the focused project's color behind the cards.
            RadialGradient(colors: [accent.base.opacity(0.22), accent.base.opacity(0)], center: .center,
                           startRadius: 10, endRadius: 320)
                .frame(height: 640)
                .offset(y: 120)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: accent)
        }
        .onAppear(perform: ensureFocus)
        .onChange(of: focusedID) { Haptics.select() }
    }

    private func ensureFocus() {
        if focusedID == nil || !ids.contains(focusedID!) {
            focusedID = (projects.first { $0.phase() == .building } ?? projects.last)?.id ?? Self.createID
        }
    }

    // MARK: Header

    private var reviewWaiting: Bool {
        _ = watchedWeek
        return WeeklyReview.isWaiting()
    }

    /// Sunday evening until watched: this week's review.
    private var reviewChip: some View {
        Button {
            Haptics.select()
            onReview()
        } label: {
            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(.white)
                    Circle().strokeBorder(Color(hex: 0xFFC800), lineWidth: 2.5)
                    Image(systemName: "play.fill").font(.system(size: 17)).foregroundStyle(Accent.sale.text)
                }
                .frame(width: 46, height: 46)
                Text("Week \(WeeklyReview.calendar.component(.weekOfYear, from: WeeklyReview.reviewWeekStart()))")
                    .display(11, 800)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(Capsule().fill(.white))
                    .overlay(Capsule().strokeBorder(Color(hex: 0xFFC800), lineWidth: 2))
                    .fixedSize()
            }
            .shadow(color: Color(hex: 0xFFC800).opacity(0.45), radius: 10)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel("Weekly review ready")
    }

    private var streakBadge: some View {
        Button {
            Haptics.select()
            onStreak()
        } label: { streakBadgeLabel }
        .buttonStyle(PressableStyle(scale: 0.92))
    }

    private var streakBadgeLabel: some View {
        // Gray until something today counts; then the whole badge lights up.
        let lit = Streak.isActiveToday(profile)
        let tint = lit ? Theme.flame : Theme.tertiary
        return VStack(spacing: -6) {
            ZStack {
                Circle().fill(.white)
                Circle().strokeBorder(tint.opacity(0.9), lineWidth: 2.5)
                FlameMark(color: tint, lit: lit)
                    .frame(height: 23)
                    .offset(y: -1)
            }
            .frame(width: 46, height: 46)
            Text("\(profile.streak)")
                .display(13, 800)
                .foregroundStyle(lit ? Theme.ink : Theme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 1)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(tint.opacity(0.9), lineWidth: 2))
                .contentTransition(.numericText())
        }
        .animation(.easeInOut(duration: 0.4), value: lit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.streak) day streak\(Streak.isActiveToday(profile) ? "" : ", nothing done yet today")")
    }

    // MARK: Carousel

    private func carousel(cardW: CGFloat, screenW: CGFloat) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(projects) { p in
                    Button {
                        if p.id == focusedID {
                            onOpen(p, cardFrames[p.id])
                        } else {
                            // Side cards come to the center first.
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { focusedID = p.id }
                        }
                    } label: {
                        ProjectCardFace(project: p, refresher: refresher)
                            .frame(width: cardW)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                cardFrames[p.id] = frame
                                if p.id == focusedID { DashLayout.lastCardFrame = frame }
                            }
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .id(p.id)
                    .modifier(CarouselEffect(step: cardW + spacing))
                }
                Button(action: onCreate) {
                    CreateProjectCardFace(subtitle: "Your rhythm: every \(profile.newProjectEveryDays.durationText)")
                        .frame(width: cardW)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrames[Self.createID] = $0 }
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .id(Self.createID)
                .modifier(CarouselEffect(step: cardW + spacing))
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focusedID, anchor: .center)
        .contentMargins(.horizontal, (screenW - cardW) / 2, for: .scrollContent)
        .scrollClipDisabled()
        // One floor shadow under the centered card (side cards tilt away from it).
        .background(alignment: .bottom) {
            Color.clear.frame(width: cardW, height: 1)
                .cardFloorShadow(width: cardW)
        }
        // The card width settles after the first layout pass; keep the focused card centered through it.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { userScrolled = true }
        }
        .task {
            ensureFocus()
            // Lazy content and the measured card width settle over the first frames.
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(60))
                guard !userScrolled else { return }
                proxy.scrollTo(focusedID, anchor: .center)
            }
            // Safety net: whatever ends up centered is what the panel, colors and button describe.
            try? await Task.sleep(for: .milliseconds(150))
            guard !userScrolled else { return }
            if let centered = cardFrames.min(by: { abs($0.value.midX - screenW / 2) < abs($1.value.midX - screenW / 2) })?.key,
               centered != focusedID {
                focusedID = centered
            }
        }
        .onChange(of: cardW) { if !userScrolled { proxy.scrollTo(focusedID, anchor: .center) } }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(ids, id: \.self) { id in
                Capsule()
                    .fill(id == focusedID ? Theme.ink : Theme.secondary.opacity(0.55))
                    .frame(width: id == focusedID ? 26 : 7, height: 7)
                    .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { focusedID = id } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focusedID)
    }

    // MARK: Panel

    @ViewBuilder
    private var infoPanel: some View {
        if let p = focused {
            ProjectPanel(project: p) { onOpen(p, cardFrames[p.id]) }
        } else {
            // Same type, spacing and two-line text area as a project's panel, so the button doesn't jump.
            VStack(alignment: .leading, spacing: 12) {
                Text(projects.isEmpty
                     ? "Start your first build: pick a cover, set the clock, connect your numbers."
                     : "Next project due \(ScheduleEngine.nextProjectDate(projects: projects, profile: profile).shortDay). New builds every \(profile.newProjectEveryDays.durationText).")
                    .font(.ui(18))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.85)
                MetaRow(items: [("clock", "~2 min setup"), ("photo", "Cover photo"), ("bolt.fill", "Live data")])
                Button("Create project", action: onCreate)
                    .buttonStyle(.chunky)
                    .padding(.top, 4)
            }
        }
    }
}

/// Rotates and shrinks cards as they move away from the center.
private struct CarouselEffect: ViewModifier {
    let step: CGFloat
    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            let frame = proxy.frame(in: .scrollView(axis: .horizontal))
            let width = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? frame.width
            let progress = min(max((frame.midX - width / 2) / step, -1.6), 1.6)
            return view
                .rotation3DEffect(.degrees(Double(progress) * -32), axis: (x: 0, y: 1, z: 0),
                                  anchor: progress > 0 ? .leading : .trailing, perspective: 0.55)
                .scaleEffect(1 - abs(progress) * 0.1)
                .offset(x: -progress * 18)
        }
    }
}

struct MetaRow: View {
    let items: [(String, String)]
    var body: some View {
        HStack(spacing: 18) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Image(systemName: items[i].0).font(.system(size: 14, weight: .semibold))
                    Text(items[i].1).font(.ui(15, .medium)).lineLimit(1)
                }
                .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Description + meta + CTA for the focused project.
struct ProjectPanel: View {
    let project: Project
    var onOpen: () -> Void
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var allProjects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary)
                .font(.ui(18))
                .foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
            MetaRow(items: meta)
            if ScheduleEngine.canShip(project) {
                Button("Let's ship") {
                    guard let profile = profiles.first else { return }
                    ScheduleEngine.shipNow(project, profile: profile, projects: allProjects, celebration: celebration, context: context)
                }
                .buttonStyle(.chunky)
                .padding(.top, 4)
            } else {
                Button("Open project", action: onOpen)
                    .buttonStyle(.chunky)
                    .padding(.top, 4)
            }
        }
    }

    private var summary: String {
        let next = project.nextMilestone
        switch project.phase() {
        case .upcoming:
            return "Kicks off \(project.startDate.shortDay). \(project.buildDays.durationText) of building ahead."
        case .building where ScheduleEngine.canShip(project):
            let early = Date.days(from: .now, to: project.launchDay)
            return early > 0 ? "Every goal is done. Ship today and you're \(early) day\(early == 1 ? "" : "s") early." : "Every goal is done. It's launch day."
        case .building:
            let n = next.map { " Next up: \($0.title) on \($0.dueDate.formatted(.dateTime.weekday(.wide)))." } ?? ""
            return "Day \(project.dayInPhase) of \(project.buildDays) in the build phase.\(n)"
        case .observing:
            return "Shipped. Watching traction for \(project.daysLeftInPhase.durationText) more."
        case .finished:
            switch project.verdict {
            case .pivot: return "Pivoted on \(project.verdictAt?.shortDay ?? "–"). The next version took over."
            case .kill: return "Killed on \(project.verdictAt?.shortDay ?? "–"). Lessons kept, time freed."
            default: return "Wrapped up on \(project.observeEnd.adding(days: -1).shortDay). Decision time: keep, pivot or kill?"
            }
        }
    }

    private var meta: [(String, String)] {
        var items: [(String, String)] = []
        switch project.phase() {
        case .upcoming: items.append(("hourglass", "in \(project.daysLeftInPhase)d"))
        case .building, .observing: items.append(("clock", "\(project.daysLeftInPhase)d left"))
        case .finished:
            if let v = project.verdict, v != .keep { items.append((v.symbol, v.pastTense)) }
            else { items.append(("scalemass", "Decide")) }
        }
        let done = project.sortedMilestones.filter(\.isDone).count
        items.append(("checkmark.circle", "\(done)/\(project.sortedMilestones.count)"))
        let momentum = project.phase() == .building ? Momentum.make(project: project) : nil
        if let m = momentum, m.hasCommitData {
            items.append(("chevron.left.forwardslash.chevron.right", "\(m.totalCommits) commits"))
        } else if let v = refresher.value(.visits, for: project) {
            items.append(("globe", MetricKey.count(v)))
        } else {
            items.append(("bolt.fill", project.hasDataSource ? "Connected" : "Sample"))
        }
        return items
    }
}
