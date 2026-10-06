import SwiftUI

/// The Sunday-evening story. Every scene is the same frame: a 3D stage (extruded numbers, blocks
/// standing on a tilted floor, cards stacked in depth) and a caption underneath. The camera makes one
/// small orbit per scene and comes to rest dead center; focus pulls bring each element sharp in turn.
/// No sound, a light haptic on each pull.
struct WeeklyReviewView: View {
    let stats: WeekStats
    let profile: Profile
    var onClose: () -> Void

    @State private var index = 0
    /// 0 → 1, linear across the scene (progress bar).
    @State private var t: CGFloat = 0
    /// 0 → 1, eased: the camera arriving at its resting pose.
    @State private var cam: CGFloat = 0
    /// Which element is in focus.
    @State private var step = 0
    @State private var paused = false
    @State private var shareImage: UIImage?

    /// Same text inset as Dash and the screen headers.
    static let inset: CGFloat = 24
    static let stageHeight: CGFloat = 340
    static let captionHeight: CGFloat = 150
    private static let focusPull = Animation.spring(response: 0.42, dampingFraction: 0.9)

    private var copy: ReviewCopy { ReviewCopy(stats: stats) }

    enum Scene: Equatable {
        case intro, days, xp, goals, commits, traction, project, next, outro

        var duration: Double {
            switch self {
            case .intro: 3.4
            case .days, .goals, .next: 3.9
            case .outro: 0
            default: 3.4
            }
        }

        /// When each focus pull happens, in seconds from the scene's start.
        var steps: [Double] {
            switch self {
            case .intro: [0, 0.35, 0.8]
            case .days: [0] + (0..<7).map { 0.3 + Double($0) * 0.11 } + [1.2]
            case .xp: [0, 0.3, 0.9]
            case .goals: [0, 0.3, 0.75, 1.2, 1.65, 2.1]
            case .commits: [0, 0.3, 0.9, 1.2]
            case .traction: [0, 0.3, 0.8]
            case .project: [0, 0.3, 0.8]
            case .next: [0, 0.3, 0.55, 0.8, 1.2]
            case .outro: [0, 0.3, 0.6]
            }
        }

        var tint: Int {
            switch self {
            case .intro, .traction, .outro: 0xFF9600
            case .days, .project: 0x58CC02
            case .xp: 0xFFC800
            case .goals, .next: 0x1CB0F6
            case .commits: 0xA35CFF
            }
        }

        /// Where the camera starts its orbit; it always ends at rest.
        var orbit: (yaw: Double, pitch: Double, zoom: CGFloat) {
            switch self {
            case .intro: (-10, 8, 0.9)
            case .days: (12, 6, 0.94)
            case .xp: (-8, -6, 0.92)
            case .goals: (0, 12, 0.92)
            case .commits: (-14, 4, 0.94)
            case .traction: (8, 6, 0.92)
            case .project: (12, -6, 0.94)
            case .next: (0, 10, 0.95)
            case .outro: (0, 6, 0.96)
            }
        }
    }

    private var scenes: [Scene] {
        var s: [Scene] = [.intro, .days, .xp, .goals]
        if stats.totalCommits > 0 { s.append(.commits) }
        if stats.visitsGained > 0 || stats.revenueGained > 0 { s.append(.traction) }
        if stats.projectOfWeek != nil { s.append(.project) }
        s += [.next, .outro]
        return s
    }

    private var scene: Scene { scenes[min(index, scenes.count - 1)] }
    private var tint: Accent { Accent(hex: scene.tint) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Holds the space; the real bar sits above the tap layer (see the overlay below).
                topBar.hidden()
                Spacer(minLength: 0)
                Group {
                    if scene == .outro {
                        outro
                    } else {
                        VStack(spacing: 0) {
                            stage
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.stageHeight)
                                .modifier(Orbit(orbit: scene.orbit, cam: cam))
                            caption
                                .frame(maxWidth: .infinity, alignment: .top)
                                .frame(height: Self.captionHeight, alignment: .top)
                        }
                    }
                }
                .padding(.horizontal, Self.inset)
                .id(index)
                .transition(.opacity)
                Spacer(minLength: 0)
                Text(scene == .outro ? " " : "Tap for next · hold to pause")
                    .font(.ui(13, .medium)).foregroundStyle(Theme.tertiary)
                    .padding(.bottom, 12)
                    .opacity(index == 0 ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        // On the container, so the close and outro buttons keep their own taps.
        .onTapGesture(coordinateSpace: .local) { p in
            guard scene != .outro else { return }
            if p.x < 110 { back() } else { advance() }
        }
        .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { paused = $0 })
        .overlay(alignment: .top) { topBar }
        // A background, not a ZStack layer: the blobs are wider than the screen and must not widen the layout.
        .background { backdrop }
        .statusBarHidden()
        .environment(\.accent, tint)
        .task(id: index) { await play() }
        .onAppear { WeeklyReview.markWatched(stats.start) }
    }

    // MARK: Timing

    private func play() async {
        let s = scene
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { t = 0; cam = 0; step = 0 }
        withAnimation(.linear(duration: max(s.duration, 0.1))) { t = 1 }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: max(s.duration * 0.9, 1.4))) { cam = 1 }
        var elapsed = 0.0
        for (i, at) in s.steps.enumerated() {
            if !(await wait(at - elapsed)) { return }
            elapsed = at
            withAnimation(Self.focusPull) { step = i + 1 }
            if i > 0 { Haptics.soft() }
        }
        guard s.duration > 0 else { return }
        if await wait(s.duration - elapsed) { advance() }
    }

    /// Sleeps, holding while the screen is pressed. False if the scene changed meanwhile.
    private func wait(_ seconds: Double) async -> Bool {
        var left = max(0, seconds)
        while left > 0 {
            if Task.isCancelled { return false }
            let chunk = min(left, 0.05)
            try? await Task.sleep(for: .seconds(chunk))
            if !paused { left -= chunk }
        }
        return !Task.isCancelled
    }

    private func advance() {
        guard index < scenes.count - 1 else { return }
        Haptics.select()
        withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
    }

    private func back() {
        guard index > 0 else { return }
        Haptics.select()
        withAnimation(.easeInOut(duration: 0.25)) { index -= 1 }
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(scenes.indices, id: \.self) { i in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.12))
                            Capsule().fill(Theme.ink)
                                .frame(width: geo.size.width * (i < index ? 1 : i == index ? (scene == .outro ? 1 : t) : 0))
                        }
                    }
                    .frame(height: 3)
                }
            }
            HStack {
                Text("WEEK \(stats.week)").eyebrow()
                Spacer()
                CircleIconButton(systemName: "xmark") { onClose() }
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 8)
    }

    private var backdrop: some View {
        Theme.background
            .overlay {
                ZStack {
                    Circle().fill(tint.base.opacity(0.2)).frame(width: 420).blur(radius: 90).offset(x: -110, y: -240)
                    Circle().fill(tint.base.opacity(0.12)).frame(width: 360).blur(radius: 90).offset(x: 130, y: 280)
                }
            }
            .clipped()
            .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: index)
    }

    // MARK: Scenes

    @ViewBuilder
    private var stage: some View {
        switch scene {
        case .intro: introStage
        case .days: daysStage
        case .xp: xpStage
        case .goals: goalsStage
        case .commits: commitsStage
        case .traction: tractionStage
        case .project: projectStage
        case .next: nextStage
        case .outro: EmptyView()
        }
    }

    private var lastStep: Int { scene.steps.count }

    @ViewBuilder
    private var caption: some View {
        VStack(spacing: 14) {
            Text(captionText)
                .font(.ui(20, .semibold)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            captionExtra
        }
        .padding(.top, 20)
        .focus(lastStep, step, dims: false)
    }

    private var captionText: String {
        switch scene {
        case .intro: copy.intro
        case .days: copy.activeDays
        case .xp: copy.xp
        case .goals: copy.goals
        case .commits: copy.commits
        case .traction: copy.traction
        case .project: stats.projectOfWeek.map { copy.projectOfWeek($0.project.name) } ?? ""
        case .next: copy.next
        case .outro: copy.outro
        }
    }

    @ViewBuilder
    private var captionExtra: some View {
        switch scene {
        case .days where stats.streak > 1:
            Label("\(stats.streak) day streak", systemImage: "flame.fill").font(.ui(15, .bold)).foregroundStyle(Theme.flame)
        case .goals where stats.checkpointsOnTime + stats.checkpointsLate + stats.slipped > 0:
            HStack(spacing: 8) {
                if stats.checkpointsOnTime > 0 { pill("\(stats.checkpointsOnTime) on time", 0x58CC02) }
                if stats.checkpointsLate > 0 { pill("\(stats.checkpointsLate) late", 0xFF9600) }
                if stats.slipped > 0 { pill("\(stats.slipped) slipped", 0xFF4B4B) }
            }
        case .next:
            Label(copy.challenge, systemImage: "target")
                .font(.ui(15, .bold)).foregroundStyle(Accent(hex: 0x1CB0F6).text)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Accent(hex: 0x1CB0F6).tint))
        default:
            EmptyView()
        }
    }

    // Intro: the week number as a solid block, standing on the floor.
    private var introStage: some View {
        VStack(spacing: 0) {
            Text("WEEKLY REVIEW").eyebrow().focus(1, step, dims: false)
            Spacer(minLength: 0)
            ExtrudedText(text: "\(stats.week)", size: 168, accent: tint)
                .focus(1, step, dims: false)
            Spacer(minLength: 0)
            Text(stats.range).font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .focus(2, step, dims: false)
        }
        .padding(.vertical, 10)
    }

    // Days: seven blocks on a tilted floor; active ones rise.
    private var daysStage: some View {
        VStack(spacing: 0) {
            ExtrudedText(text: "\(stats.activeCount)/7", size: 96, accent: tint)
                .focus(1, step, dims: false)
            Text("active days").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .padding(.top, 6)
                .focus(1, step, dims: false)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let shown = step >= i + 2
                    let lit = shown && stats.active[i]
                    VStack(spacing: 8) {
                        Block(width: 38, height: 46, depth: lit ? 9 : 5,
                              front: lit ? tint.base : Theme.card, side: lit ? tint.dark : Theme.line) {
                            if lit { Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(tint.on) }
                        }
                        .offset(y: lit ? -8 : 0)
                        Text(stats.days[i].formatted(.dateTime.weekday(.narrow))).font(.ui(12, .bold)).foregroundStyle(Theme.secondary)
                    }
                    .opacity(shown ? 1 : 0.25)
                    .animation(Self.focusPull, value: lit)
                }
            }
            .frame(maxWidth: .infinity)
            .rotation3DEffect(.degrees(24), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .background(alignment: .bottom) { FloorShadow(width: 300) }
        }
        .padding(.vertical, 10)
    }

    // XP: a gold coin turned toward the light, and the number.
    private var xpStage: some View {
        let xp = step >= 2 ? stats.xp : 0
        return VStack(spacing: 0) {
            Coin(size: 104, accent: tint)
                .rotation3DEffect(.degrees(-24 + 10 * Double(cam)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .background(alignment: .bottom) { FloorShadow(width: 110).offset(y: 22) }
                .focus(1, step, dims: false)
            Spacer(minLength: 0)
            ExtrudedText(text: "+\(xp)", size: 96, accent: tint)
                .contentTransition(.numericText(value: Double(xp)))
                .animation(.easeOut(duration: 0.8), value: xp)
                .focus(1, step, dims: false)
            Text("XP · level \(profile.level)").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .padding(.top, 6)
                .focus(2, step, dims: false)
        }
        .padding(.vertical, 10)
    }

    // Goals: the finished goals as cards stacked in depth; focus moves front to back.
    private var goalsStage: some View {
        let titles = Array(stats.goalTitles.prefix(4))
        let focused = max(0, min(titles.count - 1, step - 2))
        return VStack(spacing: 0) {
            ExtrudedText(text: "\(stats.goalsDone)", size: 96, accent: tint)
                .focus(1, step, dims: false)
            Text(stats.goalsDone == 1 ? "goal done" : "goals done").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .padding(.top, 6)
                .focus(1, step, dims: false)
            Spacer(minLength: 0)
            ZStack {
                if titles.isEmpty {
                    GoalSlab(title: "Nothing ticked yet", accent: .neutral, done: false)
                        .opacity(0.7)
                }
                ForEach(Array(titles.enumerated()).reversed(), id: \.offset) { i, g in
                    let d = CGFloat(i - focused)
                    GoalSlab(title: g.0, accent: g.1, done: true)
                        .scaleEffect(d >= 0 ? 1 - 0.07 * d : 1.05)
                        .offset(y: d >= 0 ? -16 * d : 26)
                        .blur(radius: abs(d) * 1.8)
                        .opacity(d < 0 ? 0 : 1 - 0.18 * Double(d))
                        .zIndex(-Double(i))
                }
            }
            .frame(height: 120, alignment: .bottom)
            .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .background(alignment: .bottom) { FloorShadow(width: 280) }
            .animation(Self.focusPull, value: focused)
            .focus(2, step, dims: false)
        }
        .padding(.vertical, 10)
    }

    // Commits: solid bars with real side and top faces; the busiest gets the crown.
    private var commitsStage: some View {
        let peak = max(1, stats.commits.max() ?? 1)
        return VStack(spacing: 0) {
            ExtrudedText(text: "\(stats.totalCommits)", size: 96, accent: tint)
                .focus(1, step, dims: false)
            Text(stats.totalCommits == 1 ? "commit" : "commits").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .padding(.top, 6)
                .focus(1, step, dims: false)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<7, id: \.self) { i in
                    let top = i == stats.busiestDay
                    let h: CGFloat = step >= 2 ? max(4, 120 * CGFloat(stats.commits[i]) / CGFloat(peak)) : 4
                    VStack(spacing: 6) {
                        Image(systemName: "crown.fill").font(.system(size: 15)).foregroundStyle(Color(hex: 0xFFC800))
                            .opacity(top && step >= 3 ? 1 : 0)
                            .scaleEffect(top && step >= 3 ? 1 : 0.6)
                        IsoBar(height: h, accent: top ? tint : Accent(hex: 0xD7BFFF))
                        Text(stats.days[i].formatted(.dateTime.weekday(.narrow))).font(.ui(12, .bold)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) { FloorShadow(width: 300).offset(y: -14) }
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: step)
        }
        .padding(.vertical, 10)
    }

    // Traction: what came in, as solid numbers.
    private var tractionStage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if stats.revenueGained > 0 {
                VStack(spacing: 6) {
                    ExtrudedText(text: "+" + MetricKey.money(stats.revenueGained), size: 80, accent: .sale)
                    Text("revenue").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                }
                .focus(1, step, dims: false)
            }
            if stats.visitsGained > 0 {
                VStack(spacing: 6) {
                    ExtrudedText(text: "+" + MetricKey.count(stats.visitsGained), size: stats.revenueGained > 0 ? 56 : 80, accent: tint)
                    Text("visits").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                }
                .focus(stats.revenueGained > 0 ? 2 : 1, step, dims: false)
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { FloorShadow(width: 260) }
    }

    // Project of the week: its card as a solid tile, turned a little toward you.
    @ViewBuilder
    private var projectStage: some View {
        if let best = stats.projectOfWeek {
            VStack(spacing: 0) {
                Text("PROJECT OF THE WEEK").eyebrow().focus(1, step, dims: false)
                Spacer(minLength: 0)
                Block(width: 200, height: 240, depth: 12, radius: 30,
                      front: best.project.accent.base, side: best.project.accent.dark) {
                    ZStack(alignment: .bottomLeading) {
                        if let cover = best.project.cover {
                            Image(uiImage: cover).resizable().scaledToFill().frame(width: 200, height: 240).clipped()
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(best.project.name).display(26, 800).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                            Text([best.goals > 0 ? "\(best.goals) goal\(best.goals == 1 ? "" : "s")" : nil,
                                  best.commits > 0 ? "\(best.commits) commit\(best.commits == 1 ? "" : "s")" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.ui(13, .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(16)
                    }
                    .frame(width: 200, height: 240)
                }
                .rotation3DEffect(.degrees(-14), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(6), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .background(alignment: .bottom) { FloorShadow(width: 220).offset(y: 18) }
                .focus(1, step, dims: false)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
    }

    // Next week: the coming checkpoints as tiles running back along the floor.
    private var nextStage: some View {
        let rows = Array(stats.upcoming.prefix(3))
        return VStack(spacing: 0) {
            Text("NEXT WEEK").eyebrow().focus(1, step, dims: false)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                if rows.isEmpty {
                    GoalSlab(title: "Nothing due. Suspiciously free.", accent: .neutral, done: false)
                        .focus(2, step, dims: false)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { i, u in
                    Block(height: 58, depth: 6, radius: 18, front: Theme.card, side: Theme.line) {
                        HStack(spacing: 12) {
                            Circle().fill(u.accent.base).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(u.project).font(.ui(13)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(u.due.formatted(.dateTime.weekday(.abbreviated))).font(.ui(14, .bold)).foregroundStyle(u.accent.text)
                        }
                        .padding(.horizontal, 16)
                    }
                    .focus(i + 2, step, dims: false)
                }
            }
            .rotation3DEffect(.degrees(22), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.45)
            .background(alignment: .bottom) { FloorShadow(width: 300) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var outro: some View {
        VStack(spacing: 24) {
            Block(height: WeekSummaryCard.height, depth: 8, radius: 28, front: Theme.card, side: Theme.line) {
                WeekSummaryCard(stats: stats)
            }
            .modifier(Orbit(orbit: scene.orbit, cam: cam))
            .focus(1, step, dims: false)
            Text(copy.outro).font(.ui(20, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(2, step, dims: false)
            VStack(spacing: 10) {
                Button("Let's go") { onClose() }.buttonStyle(.chunky)
                if let shareImage {
                    ShareLink(item: Image(uiImage: shareImage), preview: SharePreview("Week \(stats.week)", image: Image(uiImage: shareImage))) {
                        Label("Share my week", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.chunky(.neutral, height: 50))
                }
            }
            .focus(3, step, dims: false)
        }
        .onAppear {
            let r = ImageRenderer(content: WeekSummaryCard(stats: stats)
                .frame(width: 354, height: WeekSummaryCard.height)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.card))
                .padding(20).background(Theme.background))
            r.scale = 3
            shareImage = r.uiImage
        }
    }

    private func pill(_ text: String, _ hex: Int) -> some View {
        Text(text).font(.ui(14, .bold)).foregroundStyle(Accent(hex: hex).text)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Accent(hex: hex).tint))
    }
}

/// The week on one card: the end of the story and the image that gets shared.
struct WeekSummaryCard: View {
    static let height: CGFloat = 222
    let stats: WeekStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(stats.week)").display(30, 850).foregroundStyle(Theme.ink)
                Spacer()
                Text(stats.range).font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(stats.active[i] ? Color(hex: 0x58CC02) : Theme.line)
                        .frame(height: 26)
                }
            }
            HStack(spacing: 10) {
                tile("\(stats.activeCount)/7", "active days")
                tile("+\(stats.xp)", "XP")
                tile("\(stats.goalsDone)", "goals")
            }
            HStack(spacing: 6) {
                Image("Mark").resizable().renderingMode(.template).scaledToFit().frame(width: 13, height: 13)
                Text("Prodline weekly review").font(.ui(11, .bold))
            }
            .foregroundStyle(Theme.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).display(24, 800).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.ui(12, .semibold)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.background))
    }
}

// MARK: - 3D pieces

/// A rounded slab with thickness, content on its face.
private struct Block<Face: View>: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var depth: CGFloat
    var radius: CGFloat = 12
    let front: Color
    let side: Color
    @ViewBuilder var face: Face

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(side).offset(y: depth)
            shape.fill(front)
            face.clipShape(shape)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .padding(.bottom, depth)
    }
}

/// A gold coin with an edge and a star.
private struct Coin: View {
    let size: CGFloat
    let accent: Accent

    var body: some View {
        ZStack {
            ForEach((1...8).reversed(), id: \.self) { i in
                Circle().fill(accent.dark).offset(x: CGFloat(i) * 1.1)
            }
            Circle().fill(accent.base)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 5).padding(9)
            Image(systemName: "star.fill").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// A bar with a front, a side and a top face.
private struct IsoBar: View {
    let height: CGFloat
    let accent: Accent
    private let width: CGFloat = 26
    private let skew: CGFloat = 9

    var body: some View {
        Canvas { ctx, size in
            let base = size.height
            let front = CGRect(x: 0, y: base - height, width: width, height: height)
            ctx.fill(Path(front), with: .color(accent.base))
            var side = Path()
            side.move(to: CGPoint(x: width, y: base - height))
            side.addLine(to: CGPoint(x: width + skew, y: base - height - skew))
            side.addLine(to: CGPoint(x: width + skew, y: base - skew))
            side.addLine(to: CGPoint(x: width, y: base))
            ctx.fill(side, with: .color(accent.dark))
            var top = Path()
            top.move(to: CGPoint(x: 0, y: base - height))
            top.addLine(to: CGPoint(x: skew, y: base - height - skew))
            top.addLine(to: CGPoint(x: width + skew, y: base - height - skew))
            top.addLine(to: CGPoint(x: width, y: base - height))
            ctx.fill(top, with: .color(accent.base.opacity(0.75)))
        }
        .frame(width: width + skew, height: 120 + skew)
    }
}

/// A finished goal as a card with thickness.
private struct GoalSlab: View {
    let title: String
    let accent: Accent
    let done: Bool

    var body: some View {
        Block(height: 58, depth: 6, radius: 18, front: Theme.card, side: Theme.line) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 18)).foregroundStyle(done ? accent.base : Theme.tertiary)
                Text(title).font(.ui(16, .semibold)).foregroundStyle(done ? Theme.ink : Theme.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Soft contact shadow that grounds objects on the floor.
private struct FloorShadow: View {
    let width: CGFloat

    var body: some View {
        Ellipse().fill(Color.black.opacity(0.12)).frame(width: width, height: 26).blur(radius: 14)
    }
}

// MARK: - Camera and focus

/// One small orbit per scene: starts turned and pulled back, settles at exactly the resting pose.
private struct Orbit: ViewModifier {
    let orbit: (yaw: Double, pitch: Double, zoom: CGFloat)
    let cam: CGFloat

    func body(content: Content) -> some View {
        let r = 1 - Double(cam)
        content
            .rotation3DEffect(.degrees(orbit.yaw * r), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .rotation3DEffect(.degrees(orbit.pitch * r), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
            .scaleEffect(orbit.zoom + (1 - orbit.zoom) * cam)
    }
}

private struct Focus: ViewModifier {
    let index: Int
    let step: Int
    /// Soften once the focus has moved past it.
    let dims: Bool

    func body(content: Content) -> some View {
        let before = step < index
        let after = step > index && dims
        content
            .blur(radius: before ? 12 : after ? 0.8 : 0)
            .opacity(before ? 0 : after ? 0.7 : 1)
            .scaleEffect(before ? 0.96 : 1)
    }
}

private extension View {
    func focus(_ index: Int, _ step: Int, dims: Bool = true) -> some View {
        modifier(Focus(index: index, step: step, dims: dims))
    }
}
