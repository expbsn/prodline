import SwiftUI

/// The Sunday-evening story. Motion stays small: a slow camera move per scene (push-in, pan or tilt)
/// and a rack focus that pulls each element sharp in turn while the earlier ones soften. No sound;
/// a light haptic marks each focus pull.
struct WeeklyReviewView: View {
    let stats: WeekStats
    let profile: Profile
    var onClose: () -> Void

    @State private var index = 0
    /// 0 → 1 across the scene: drives the camera and the progress bar.
    @State private var t: CGFloat = 0
    /// Which element is in focus.
    @State private var step = 0
    @State private var paused = false
    @State private var shareImage: UIImage?

    private var copy: ReviewCopy { ReviewCopy(stats: stats) }

    enum Scene: Equatable {
        case intro, days, xp, goals, commits, traction, project, next, outro

        var duration: Double {
            switch self {
            case .intro: 5.2
            case .days: 6.2
            case .outro: 0
            default: 5.6
            }
        }

        /// When each focus pull happens, in seconds from the scene's start.
        var steps: [Double] {
            switch self {
            case .intro: [0.1, 0.8, 1.9, 2.8]
            case .days: [0.1] + (0..<7).map { 0.7 + Double($0) * 0.32 } + [3.4]
            case .xp: [0.1, 0.6, 2.2, 3.0]
            case .goals: [0.1, 0.7, 1.3, 1.9, 2.5, 3.3]
            case .commits: [0.1, 0.7, 2.0, 3.0]
            case .traction: [0.1, 0.9, 2.0]
            case .project: [0.1, 0.8, 1.8]
            case .next: [0.1, 0.7, 1.3, 1.9, 2.8]
            case .outro: [0.2, 0.7, 1.2]
            }
        }

        enum Move { case pushIn, panLeft, tiltUp }
        var move: Move {
            switch self {
            case .days, .commits: .panLeft
            case .project, .next: .tiltUp
            default: .pushIn
            }
        }

        var tint: Int {
            switch self {
            case .intro: 0x1C1C1E
            case .days: 0x58CC02
            case .xp: 0xFFC800
            case .goals: 0x1CB0F6
            case .commits: 0xA35CFF
            case .traction: 0xFF9600
            case .project: 0x58CC02
            case .next: 0x1CB0F6
            case .outro: 0xFF9600
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

    var body: some View {
        ZStack {
            backdrop
            content
                .modifier(Camera(t: t, move: scene.move))
                .padding(.horizontal, 28)
                .id(index)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            tapZones
            VStack(spacing: 14) {
                progressBars
                HStack {
                    Text("WEEK \(stats.week)").font(.ui(12, .bold)).tracking(1.2).foregroundStyle(Theme.secondary)
                    Spacer()
                    CircleIconButton(systemName: "xmark") { close() }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .statusBarHidden()
        .task(id: index) { await play() }
    }

    // MARK: Timing

    private func play() async {
        let s = scene
        t = 0
        step = 0
        withAnimation(.linear(duration: max(s.duration, 6))) { t = 1 }
        var elapsed = 0.0
        for (i, at) in s.steps.enumerated() {
            if !(await wait(at - elapsed)) { return }
            elapsed = at
            withAnimation(.easeInOut(duration: 0.85)) { step = i + 1 }
            Haptics.soft()
        }
        guard s.duration > 0 else { return }
        if await wait(s.duration - elapsed) { advance() }
    }

    /// Sleeps, holding while the screen is pressed. False if the scene changed meanwhile.
    private func wait(_ seconds: Double) async -> Bool {
        var left = max(0, seconds)
        while left > 0 {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(100))
            if !paused { left -= 0.1 }
        }
        return !Task.isCancelled
    }

    private func advance() {
        guard index < scenes.count - 1 else { return }
        Haptics.select()
        withAnimation(.easeInOut(duration: 0.5)) { index += 1 }
    }

    private func back() {
        guard index > 0 else { return }
        Haptics.select()
        withAnimation(.easeInOut(duration: 0.5)) { index -= 1 }
    }

    private func close() {
        WeeklyReview.markWatched(stats.start)
        onClose()
    }

    // MARK: Chrome

    private var progressBars: some View {
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
    }

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).frame(maxWidth: 110).onTapGesture { back() }
            Color.clear.contentShape(Rectangle()).onTapGesture { advance() }
        }
        .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { paused = $0 })
        .allowsHitTesting(scene != .outro)
    }

    /// Soft color field for the scene; it drifts a little less than the content, which gives depth.
    private var backdrop: some View {
        let tint = Accent(hex: scene.tint)
        return ZStack {
            Theme.background
            Circle().fill(tint.base.opacity(0.22)).frame(width: 420).blur(radius: 90)
                .offset(x: -120 + 40 * t, y: -260 + 20 * t)
            Circle().fill(tint.base.opacity(0.14)).frame(width: 360).blur(radius: 90)
                .offset(x: 140 - 30 * t, y: 300 - 24 * t)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: index)
    }

    // MARK: Scenes

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .intro: intro
        case .days: activeDays
        case .xp: xpScene
        case .goals: goalsScene
        case .commits: commitsScene
        case .traction: tractionScene
        case .project: projectScene
        case .next: nextScene
        case .outro: outro
        }
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Text("WEEKLY REVIEW").font(.ui(13, .bold)).tracking(2).foregroundStyle(Theme.secondary)
                .focus(1, step)
            VStack(spacing: -10) {
                Text("Week").display(34, 700).foregroundStyle(Theme.secondary)
                Text("\(stats.week)").display(190, 850).foregroundStyle(Theme.ink).monospacedDigit()
            }
            .focus(2, step, dims: false)
            Text(stats.range).font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .focus(3, step)
            Text(copy.intro).font(.ui(20, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .padding(.top, 10)
                .focus(4, step, dims: false)
        }
    }

    private var activeDays: some View {
        VStack(spacing: 26) {
            VStack(spacing: 2) {
                Text("\(stats.activeCount)/7").display(96, 850).foregroundStyle(Theme.ink).monospacedDigit()
                Text("active days").font(.ui(18, .semibold)).foregroundStyle(Theme.secondary)
            }
            .focus(1, step, dims: false)
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let lit = step >= i + 2 && stats.active[i]
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(lit ? Color(hex: 0x58CC02) : Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(lit ? Color.clear : Theme.line, lineWidth: 2))
                            .overlay(Image(systemName: lit ? "checkmark" : "").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white))
                            .frame(width: 38, height: 52)
                        Text(stats.days[i].formatted(.dateTime.weekday(.narrow))).font(.ui(12, .bold)).foregroundStyle(Theme.secondary)
                    }
                    .focus(i + 2, step, dims: false)
                }
            }
            Text(copy.activeDays).font(.ui(20, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(9, step, dims: false)
            if stats.streak > 1 {
                Label("\(stats.streak) day streak", systemImage: "flame.fill").font(.ui(15, .bold)).foregroundStyle(Theme.flame)
                    .focus(9, step, dims: false)
            }
        }
    }

    private var xpScene: some View {
        VStack(spacing: 22) {
            Image(systemName: "star.fill").font(.system(size: 44)).foregroundStyle(Color(hex: 0xFFC800))
                .focus(1, step)
            Text("+\(step >= 2 ? stats.xp : 0)").display(110, 850).foregroundStyle(Theme.ink).monospacedDigit()
                .lineLimit(1).fixedSize()
                .contentTransition(.numericText(value: Double(step >= 2 ? stats.xp : 0)))
                .animation(.easeOut(duration: 1.4), value: step >= 2)
                .focus(2, step, dims: false)
            Text("XP this week · level \(profile.level)").font(.ui(17, .semibold)).foregroundStyle(Theme.secondary)
                .focus(3, step)
            Text(copy.xp).font(.ui(20, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(4, step, dims: false)
        }
    }

    private var goalsScene: some View {
        VStack(spacing: 18) {
            VStack(spacing: 0) {
                Text("\(stats.goalsDone)").display(96, 850).foregroundStyle(Theme.ink).monospacedDigit()
                Text(stats.goalsDone == 1 ? "goal done" : "goals done").font(.ui(18, .semibold)).foregroundStyle(Theme.secondary)
            }
            .focus(1, step, dims: false)
            VStack(spacing: 8) {
                ForEach(Array(stats.goalTitles.prefix(4).enumerated()), id: \.offset) { i, g in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(g.1.base)
                        Text(g.0).font(.ui(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                    .focus(i + 2, step)
                }
            }
            if stats.checkpointsOnTime + stats.checkpointsLate + stats.slipped > 0 {
                HStack(spacing: 8) {
                    if stats.checkpointsOnTime > 0 { pill("\(stats.checkpointsOnTime) on time", 0x58CC02) }
                    if stats.checkpointsLate > 0 { pill("\(stats.checkpointsLate) late", 0xFF9600) }
                    if stats.slipped > 0 { pill("\(stats.slipped) slipped", 0xFF4B4B) }
                }
                .focus(6, step, dims: false)
            }
            Text(copy.goals).font(.ui(19, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(6, step, dims: false)
        }
    }

    private var commitsScene: some View {
        let peak = max(1, stats.commits.max() ?? 1)
        return VStack(spacing: 24) {
            VStack(spacing: 0) {
                Text("\(stats.totalCommits)").display(96, 850).foregroundStyle(Theme.ink).monospacedDigit()
                Text("commits").font(.ui(18, .semibold)).foregroundStyle(Theme.secondary)
            }
            .focus(1, step, dims: false)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    let n = stats.commits[i]
                    let top = i == stats.busiestDay
                    VStack(spacing: 6) {
                        Image(systemName: "crown.fill").font(.system(size: 16)).foregroundStyle(Color(hex: 0xFFC800))
                            .opacity(top && step >= 3 ? 1 : 0)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(top ? Color(hex: 0xA35CFF) : Color(hex: 0xA35CFF).opacity(0.35))
                            .frame(width: 30, height: step >= 2 ? max(6, 150 * CGFloat(n) / CGFloat(peak)) : 6)
                        Text(stats.days[i].formatted(.dateTime.weekday(.narrow))).font(.ui(12, .bold)).foregroundStyle(Theme.secondary)
                    }
                    .blur(radius: step >= 3 && !top ? 1.2 : 0)
                }
            }
            .frame(height: 200, alignment: .bottom)
            .animation(.spring(response: 0.9, dampingFraction: 0.85), value: step)
            .focus(2, step, dims: false)
            Text(copy.commits).font(.ui(19, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(4, step, dims: false)
        }
    }

    private var tractionScene: some View {
        VStack(spacing: 20) {
            if stats.revenueGained > 0 {
                VStack(spacing: 0) {
                    Text("+" + MetricKey.money(stats.revenueGained)).display(76, 850).foregroundStyle(Accent.sale.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("revenue").font(.ui(18, .semibold)).foregroundStyle(Theme.secondary)
                }
                .focus(1, step, dims: false)
            }
            if stats.visitsGained > 0 {
                VStack(spacing: 0) {
                    Text("+" + MetricKey.count(stats.visitsGained)).display(stats.revenueGained > 0 ? 52 : 76, 850).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("visits").font(.ui(18, .semibold)).foregroundStyle(Theme.secondary)
                }
                .focus(stats.revenueGained > 0 ? 2 : 1, step, dims: false)
            }
            Text(copy.traction).font(.ui(19, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(3, step, dims: false)
        }
    }

    @ViewBuilder
    private var projectScene: some View {
        if let best = stats.projectOfWeek {
            VStack(spacing: 22) {
                Text("PROJECT OF THE WEEK").font(.ui(13, .bold)).tracking(2).foregroundStyle(Theme.secondary)
                    .focus(1, step)
                Color.clear
                    .frame(width: 220, height: 270)
                    .background {
                        if let cover = best.project.cover {
                            Image(uiImage: cover).resizable().scaledToFill().frame(width: 220, height: 270).clipped()
                        } else {
                            best.project.accent.base
                        }
                    }
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                    .overlay(alignment: .bottomLeading) {
                        Text(best.project.name).display(28, 800).foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.7).padding(18)
                    }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: best.project.accent.base.opacity(0.35), radius: 24, y: 12)
                .focus(2, step, dims: false)
                Text([best.goals > 0 ? "\(best.goals) goal\(best.goals == 1 ? "" : "s")" : nil,
                      best.commits > 0 ? "\(best.commits) commit\(best.commits == 1 ? "" : "s")" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.ui(16, .semibold)).foregroundStyle(Theme.secondary)
                    .focus(3, step, dims: false)
                Text(copy.projectOfWeek(best.project.name)).font(.ui(19, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    .focus(3, step, dims: false)
            }
        }
    }

    private var nextScene: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next week").display(40, 800).foregroundStyle(Theme.ink)
                .focus(1, step, dims: false)
            ForEach(Array(stats.upcoming.prefix(3).enumerated()), id: \.offset) { i, u in
                HStack(spacing: 12) {
                    Circle().fill(u.accent.base).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(u.title).font(.ui(17, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("\(u.project) · \(u.due.formatted(.dateTime.weekday(.wide)))").font(.ui(14)).foregroundStyle(Theme.secondary)
                    }
                }
                .focus(i + 2, step)
            }
            Text(copy.next).font(.ui(18, .semibold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .focus(5, step, dims: false)
            Label(copy.challenge, systemImage: "target")
                .font(.ui(16, .bold)).foregroundStyle(Accent(hex: 0x1CB0F6).text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Accent(hex: 0x1CB0F6).tint))
                .focus(5, step, dims: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outro: some View {
        VStack(spacing: 22) {
            WeekSummaryCard(stats: stats)
                .focus(1, step, dims: false)
            Text(copy.outro).font(.ui(20, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .focus(2, step, dims: false)
            VStack(spacing: 10) {
                Button("Let's go") { close() }.buttonStyle(.chunky)
                if let shareImage {
                    ShareLink(item: Image(uiImage: shareImage), preview: SharePreview("Week \(stats.week)", image: Image(uiImage: shareImage))) {
                        Label("Share my week", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.chunky(.neutral, height: 50))
                }
            }
            .focus(3, step, dims: false)
        }
        .environment(\.accent, Accent(hex: 0xFF9600))
        .onAppear {
            let r = ImageRenderer(content: WeekSummaryCard(stats: stats).padding(20).background(Theme.background))
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
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.card))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).display(24, 800).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.background))
    }
}

// MARK: - Camera and focus

/// A slow, small move over the whole scene: a few percent of zoom, a few points of travel, a few degrees of tilt.
private struct Camera: ViewModifier {
    let t: CGFloat
    let move: WeeklyReviewView.Scene.Move

    func body(content: Content) -> some View {
        switch move {
        case .pushIn:
            content
                .scaleEffect(1 + 0.05 * t)
                .offset(y: -10 * t)
        case .panLeft:
            content
                .offset(x: 12 - 24 * t)
                .rotation3DEffect(.degrees(Double(3 - 6 * t)), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        case .tiltUp:
            content
                .rotation3DEffect(.degrees(Double(7 * (1 - t))), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.4)
                .scaleEffect(1 + 0.03 * t)
                .offset(y: 12 - 18 * t)
        }
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
            .blur(radius: before ? 14 : after ? 0.8 : 0)
            .opacity(before ? 0 : after ? 0.7 : 1)
            .scaleEffect(before ? 0.96 : 1)
            .offset(y: before ? 10 : 0)
    }
}

private extension View {
    func focus(_ index: Int, _ step: Int, dims: Bool = true) -> some View {
        modifier(Focus(index: index, step: step, dims: dims))
    }
}
