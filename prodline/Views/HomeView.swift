import SwiftUI
import SwiftData

/// Projects as playing cards in a horizontal 3D carousel; the focused card drives the panel below.
struct HomeView: View {
    let profile: Profile
    @Binding var focusedID: UUID?
    let zoom: Namespace.ID
    var onOpen: (Project, CGRect?) -> Void
    var onCreate: () -> Void
    var onStreak: () -> Void

    @Query(sort: \Project.startDate) private var projects: [Project]
    @Environment(DataRefresher.self) private var refresher
    @Environment(\.modelContext) private var context
    /// On-screen frames of the cards, so the project page can put its card exactly there.
    @State private var cardFrames: [UUID: CGRect] = [:]

    static let createID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    private let spacing: CGFloat = 16

    private var focused: Project? { projects.first { $0.id == focusedID } }
    private var accent: Accent { focused?.accent ?? .neutral }
    private var ids: [UUID] { projects.map(\.id) + [Self.createID] }

    var body: some View {
        GeometryReader { geo in
            // Fit the card to the space left after header, dots and panel (~370pt) so the CTA stays visible.
            let cardW = max(150, min(geo.size.width * 0.6, (geo.size.height - 390) * 5 / 7, 300))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(eyebrow: "Prodline", title: "Projects") { streakBadge }

                    carousel(cardW: cardW, screenW: geo.size.width)
                        .padding(.top, 4)

                    dots.frame(maxWidth: .infinity).padding(.top, 22)

                    infoPanel
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
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
        .onAppear {
            if focusedID == nil || !ids.contains(focusedID!) {
                focusedID = (projects.first { $0.phase() == .building } ?? projects.last)?.id ?? Self.createID
            }
        }
        .onChange(of: focusedID) { Haptics.select() }
    }

    // MARK: Header

    private var streakBadge: some View {
        Button {
            Haptics.select()
            onStreak()
        } label: { streakBadgeLabel }
        .buttonStyle(PressableStyle(scale: 0.92))
    }

    private var streakBadgeLabel: some View {
        VStack(spacing: -6) {
            ZStack {
                Circle().fill(.white)
                Circle().strokeBorder(Theme.flame.opacity(0.9), lineWidth: 2.5)
                Image(systemName: "flame.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(profile.streak > 0 ? Theme.flame : Theme.tertiary)
                    .symbolEffect(.bounce, value: profile.streak)
            }
            .frame(width: 46, height: 46)
            Text("\(profile.streak)")
                .display(13, 800)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 1)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(Theme.flame.opacity(0.9), lineWidth: 2))
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak \(profile.streak)")
    }

    // MARK: Carousel

    private func carousel(cardW: CGFloat, screenW: CGFloat) -> some View {
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
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrames[p.id] = $0 }
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .id(p.id)
                    .modifier(CarouselEffect(step: cardW + spacing))
                }
                Button(action: onCreate) {
                    CreateProjectCardFace(subtitle: "Your rhythm: every \(profile.newProjectEveryDays.durationText)")
                        .frame(width: cardW)
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .id(Self.createID)
                .modifier(CarouselEffect(step: cardW + spacing))
            }
            .scrollTargetLayout()
            .padding(.vertical, 24)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focusedID, anchor: .center)
        .contentMargins(.horizontal, (screenW - cardW) / 2, for: .scrollContent)
        .scrollClipDisabled()
        // One floor shadow under the centered card (side cards tilt away from it).
        .background(alignment: .bottom) {
            Color.clear.frame(width: cardW, height: 1)
                .cardFloorShadow(width: cardW)
                .offset(y: -24)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(ids, id: \.self) { id in
                Capsule()
                    .fill(id == focusedID ? Theme.ink : Theme.tertiary)
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
            VStack(alignment: .leading, spacing: 14) {
                Text(projects.isEmpty
                     ? "Start your first build: pick a cover, set the clock, connect your numbers."
                     : "Next project due \(ScheduleEngine.nextProjectDate(projects: projects, profile: profile).shortDay). New builds start every \(profile.newProjectEveryDays.durationText).")
                    .font(.ui(19))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                MetaRow(items: [("clock", "~2 min setup"), ("photo", "Cover photo"), ("bolt.fill", "Live data")])
                Button("Create project", action: onCreate)
                    .buttonStyle(.chunky)
                    .padding(.top, 6)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary)
                .font(.ui(18))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            MetaRow(items: meta)
            Button("Open project", action: onOpen)
                .buttonStyle(.chunky)
                .padding(.top, 4)
        }
    }

    private var summary: String {
        let next = project.nextMilestone
        switch project.phase() {
        case .upcoming:
            return "Kicks off \(project.startDate.shortDay). \(project.buildDays.durationText) of building ahead."
        case .building:
            let n = next.map { " Next up: \($0.title) on \($0.dueDate.formatted(.dateTime.weekday(.wide)))." } ?? ""
            return "Day \(project.dayInPhase) of \(project.buildDays) in the build phase.\(n)"
        case .observing:
            return "Shipped. Watching traction for \(project.daysLeftInPhase.durationText) more."
        case .finished:
            return "Wrapped up on \(project.observeEnd.adding(days: -1).shortDay). Time to decide: double down or move on?"
        }
    }

    private var meta: [(String, String)] {
        var items: [(String, String)] = []
        switch project.phase() {
        case .upcoming: items.append(("hourglass", "in \(project.daysLeftInPhase)d"))
        case .building, .observing: items.append(("clock", "\(project.daysLeftInPhase)d left"))
        case .finished: items.append(("flag.checkered", "Done"))
        }
        let done = project.sortedMilestones.filter(\.isDone).count
        items.append(("checkmark.circle", "\(done)/\(project.sortedMilestones.count)"))
        if let v = refresher.value(.visits, for: project) {
            items.append(("globe", MetricKey.count(v)))
        } else {
            items.append(("bolt.fill", project.hasEndpoint ? "Connected" : "Sample"))
        }
        return items
    }
}
