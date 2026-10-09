import SwiftUI

/// The first onboarding screen, told on scroll. A point travels down a winding dotted line (the stretch behind
/// it turns solid). Each section pins in the middle of the screen while its scene plays out with the scroll —
/// goals ticking, the rhythm being set, the streak flame catching, shipping early, numbers coming in,
/// keep / pivot / kill — and the point runs down the lane beside it. Sections tilt back as they rise in and
/// tip forward as they leave, flat while they play. At the bottom the line runs up into the logo's stem and
/// carves the "p", like the launch animation.
struct StoryOnboarding: View {
    var onFinish: () -> Void
    @State private var offset: CGFloat = 0
    /// Measured heights of the sections; the line's lanes are cut to fit them exactly.
    @State private var heights: [CGFloat] = StoryLayout.estimates
    @State private var carved = false

    var body: some View {
        GeometryReader { geo in
            let l = StoryLayout(width: geo.size.width, height: geo.size.height, heights: heights)
            let state = l.state(scroll: offset)
            ScrollView(showsIndicators: false) {
                StoryCanvas(layout: l, state: state, heights: $heights)
                    .frame(width: l.width, height: l.scrollHeight, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in
                offset = v
            }
            .onChange(of: StoryHaptics.marks(state)) { old, new in
                // Like the weekly wrap: every event has its own feel, played when scrolling forward.
                StoryHaptics.play(from: old, to: new)
            }
            .onChange(of: state.carve >= 1) { _, done in
                if done && !carved { carved = true; Haptics.success() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Get started", action: onFinish)
                    .buttonStyle(.chunky)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .opacity(state.carve >= 0.98 ? 1 : 0)
                    .offset(y: state.carve >= 0.98 ? 0 : 30)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.carve >= 0.98)
                    .allowsHitTesting(state.carve >= 0.98)
            }
            .overlay(alignment: .top) {
                // Content fades out under the status bar instead of running behind the clock.
                LinearGradient(colors: [Theme.background, Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 36)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                // Before the first scroll: a nudge at the bottom of the screen, gone once you start.
                ScrollHint()
                    .padding(.bottom, 12)
                    .opacity(Double(max(0, 1 - offset / 80)))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button("Skip", action: onFinish)
                    .font(.ui(15, .semibold)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 24).padding(.top, 8)
                    .opacity(state.carve >= 0.98 ? 0 : 1)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// "Scroll" with a chevron that keeps nudging downward.
private struct ScrollHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Scroll").font(.ui(13, .semibold)).foregroundStyle(Theme.tertiary)
            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.tertiary)
                .phaseAnimator([0, 1]) { v, phase in
                    v.offset(y: phase * 8).opacity(1 - phase * 0.4)
                } animation: { _ in .easeInOut(duration: 0.7) }
        }
    }
}

// MARK: - Haptics

/// Countable moments in the story; a mark going up plays its haptic.
private enum StoryHaptics {
    static func marks(_ s: StoryLayout.State) -> [Int] {
        let b = s.beats
        let numbers = min(1, max(0, (b[4] - 0.1) / 0.7))
        let v = RhythmBeat.values(b[1])
        return [
            numbers >= 1 ? 1 : 0,                                       // the numbers land with a burst
            s.pinned,                                                   // a section locks in place
            [0.15, 0.3, 0.45].filter { b[0] >= $0 }.count,             // goals ticked
            v.build / 2 + v.observe / 4 + v.every / 2,                  // sliders moving
            RhythmBeat.stage(b[1]),                                     // checkpoint days changing
            b[2] >= 0.55 ? 1 : 0,                                       // the flame catches
            StreakBeat.arrived(b[2]),                                   // sparks landing on the ember
            ShipBeat.day(b[3]),                                         // the days ticking up
            b[3] >= ShipBeat.appears ? 1 : 0,                           // the ship button rises in
            b[3] >= ShipBeat.press ? 1 : 0,                             // the button sinks in
            b[3] >= ShipBeat.ships ? 1 : 0,                             // shipped
            Int(numbers * 10),                                          // numbers counting
            (0..<5).filter { b[4] >= 0.3 + Double($0) * 0.1 }.count,    // services popping in
            b[5] < 0.15 ? 0 : b[5] < 0.4 ? 1 : b[5] < 0.65 ? 2 : 3,    // kill, pivot, keep
            Int(s.carve * 8),                                           // carving the logo
        ]
    }

    static func play(from old: [Int], to new: [Int]) {
        guard old.count == new.count else { return }
        for i in new.indices where new[i] > old[i] {
            switch i {
            case 0: Haptics.success()
            case 1, 6, 8, 11, 14: Haptics.soft()
            case 5, 10: Haptics.heavy(); Haptics.success()
            case 7, 9: Haptics.tap()
            case 13 where new[i] == 3: Haptics.heavy(); Haptics.success()
            default: Haptics.select()
            }
            return
        }
    }
}

// MARK: - Geometry and timing

/// Where everything sits, the line's pieces, and how scrolling maps onto pins, progress and the point.
struct StoryLayout {
    static let count = 6
    static let estimates: [CGFloat] = [520, 470, 330, 330, 300, 250]
    /// Scroll spent on each section while it's pinned (in screen heights): long enough to watch it play.
    static let pinFactor: [CGFloat] = [1.1, 1.2, 0.9, 0.9, 0.9, 0.8]
    static let carveFactor: CGFloat = 0.7
    static let gapFactor: CGFloat = 0.26

    let width: CGFloat
    let height: CGFloat
    let heights: [CGFloat]
    let tops: [CGFloat]
    let leftLane: [Bool]
    let logoCenter: CGPoint
    let logoScale: CGFloat

    /// The line in pieces: lead-in, then lane / crossing alternating, then the approach to the logo.
    struct Segment { let path: Path; let length: CGFloat; let start: CGFloat }
    let segments: [Segment]
    let logo: Path

    /// Content offset at which each section sits centered (where it pins), and its pin length in scroll.
    let pinAt: [CGFloat]
    let pinLength: [CGFloat]
    let logoAt: CGFloat
    let carveLength: CGFloat
    let scrollHeight: CGFloat

    init(width w: CGFloat, height vh: CGFloat, heights hs: [CGFloat]) {
        width = w
        height = vh
        heights = hs
        let gap = vh * Self.gapFactor
        var t: [CGFloat] = []
        var y = vh * 0.95
        for h in hs { t.append(y); y += h + gap }
        tops = t
        leftLane = (0..<Self.count).map { $0 % 2 == 0 }
        logoScale = 170 / 850
        let lastBottom = t[Self.count - 1] + hs[Self.count - 1]
        logoCenter = CGPoint(x: w / 2 + 6, y: lastBottom + gap + vh * 0.3)
        let k = logoScale, c = logoCenter
        func L(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + (x - 600) * k, y: c.y + (y - 410) * k) }
        let laneX = { (i: Int) -> CGFloat in i % 2 == 0 ? 32 : w - 32 }

        // The pieces of the line. Lanes run exactly the height of their section; every crossing sits in the
        // empty gap between two sections, so the line never runs through one.
        var segs: [Path] = []
        let rounded = { (a: CGPoint, b: CGPoint) -> Path in
            var p = Path()
            p.move(to: a)
            let dy = b.y - a.y
            p.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + dy * 0.9), control2: CGPoint(x: b.x, y: b.y - dy * 0.9))
            return p
        }
        segs.append(rounded(CGPoint(x: w / 2, y: vh * 0.56), CGPoint(x: laneX(0), y: t[0] - 12)))
        for i in 0..<Self.count {
            let x = laneX(i)
            let bow: CGFloat = i % 2 == 0 ? -8 : 8
            var lanePath = Path()
            let a = CGPoint(x: x, y: t[i] - 12), b = CGPoint(x: x, y: t[i] + hs[i] + 12)
            lanePath.move(to: a)
            lanePath.addCurve(to: b, control1: CGPoint(x: x + bow, y: a.y + (b.y - a.y) * 0.33),
                              control2: CGPoint(x: x + bow, y: a.y + (b.y - a.y) * 0.67))
            segs.append(lanePath)
            if i < Self.count - 1 {
                segs.append(rounded(b, CGPoint(x: laneX(i + 1), y: t[i + 1] - 12)))
            }
        }
        // Round under the logo and straight up into the bottom of the stem, as in the launch animation.
        let stemBottom = L(490, 630)
        var approach = Path()
        let from = CGPoint(x: laneX(Self.count - 1), y: lastBottom + 12)
        let below = CGPoint(x: stemBottom.x, y: stemBottom.y + vh * 0.1)
        approach.move(to: from)
        approach.addCurve(to: below, control1: CGPoint(x: from.x, y: below.y + vh * 0.04), control2: CGPoint(x: below.x + 60, y: below.y + vh * 0.04))
        approach.addLine(to: stemBottom)
        segs.append(approach)

        func length(_ p: Path) -> CGFloat {
            // Walks the curves directly (cheap enough to redo on every scroll frame), so each piece's dots
            // continue the rhythm of the one before.
            var total: CGFloat = 0
            var cur = CGPoint.zero
            p.forEach { el in
                switch el {
                case .move(let to): cur = to
                case .line(let to): total += hypot(to.x - cur.x, to.y - cur.y); cur = to
                case .curve(let to, let c1, let c2):
                    var prev = cur
                    for i in 1...60 {
                        let u = CGFloat(i) / 60, v = 1 - u
                        let k0: CGFloat = v * v * v, k1: CGFloat = 3 * v * v * u, k2: CGFloat = 3 * v * u * u, k3: CGFloat = u * u * u
                        let x: CGFloat = k0 * cur.x + k1 * c1.x + k2 * c2.x + k3 * to.x
                        let y: CGFloat = k0 * cur.y + k1 * c1.y + k2 * c2.y + k3 * to.y
                        let q = CGPoint(x: x, y: y)
                        total += hypot(q.x - prev.x, q.y - prev.y)
                        prev = q
                    }
                    cur = to
                default: break
                }
            }
            return total
        }
        var acc: CGFloat = 0
        var built: [Segment] = []
        for p in segs {
            let len = length(p)
            built.append(Segment(path: p, length: len, start: acc))
            acc += len
        }
        segments = built

        var lg = Path()
        lg.move(to: L(490, 630))
        lg.addLine(to: L(490, 390))
        lg.addCurve(to: L(672, 190), control1: L(490, 250), control2: L(552, 190))
        lg.addCurve(to: L(856, 342), control1: L(792, 190), control2: L(856, 262))
        lg.addCurve(to: L(700, 490), control1: L(856, 430), control2: L(792, 490))
        lg.addLine(to: L(402, 490))
        logo = lg

        pinAt = (0..<Self.count).map { t[$0] + hs[$0] / 2 - vh * 0.5 }
        pinLength = Self.pinFactor.map { $0 * vh }
        logoAt = logoCenter.y + 40 - vh * 0.5
        carveLength = vh * Self.carveFactor
        scrollHeight = logoAt + vh + pinLength.reduce(0, +) + carveLength
    }

    struct State {
        /// How far the content has moved; it stands still while a section is pinned.
        var content: CGFloat
        /// Which piece of the line the point is on, and how far along it.
        var segment: Int
        var along: CGFloat
        var carve: CGFloat
        var beats: [CGFloat]
        /// How many sections have pinned so far.
        var pinned: Int
        var hold: CGFloat
    }

    func state(scroll s: CGFloat) -> State {
        // The timeline: free scroll, pin, free scroll, pin… then the logo pin that carves.
        var beats = Array(repeating: CGFloat(0), count: Self.count)
        var consumed: CGFloat = 0
        var pinned = 0
        var content = s
        var segment = 0
        var along: CGFloat = 0
        var carve: CGFloat = 0
        var located = false
        var prevEnd: CGFloat = 0
        for i in 0..<Self.count {
            let start = pinAt[i] + consumed
            let end = start + pinLength[i]
            if !located && s < start {
                // Between pins: the content scrolls and the point rides the crossing (or the lead-in).
                segment = i * 2
                along = min(1, max(0, (s - prevEnd) / max(1, start - prevEnd)))
                content = s - consumed
                located = true
            } else if !located && s < end {
                // Pinned: the content holds and the point runs down the lane beside the section.
                beats[i] = (s - start) / pinLength[i]
                segment = i * 2 + 1
                along = beats[i]
                content = pinAt[i]
                pinned = i + 1
                located = true
            } else if s >= end {
                beats[i] = 1
                pinned = i + 1
            }
            consumed += pinLength[i]
            prevEnd = end
        }
        if !located {
            let start = logoAt + consumed
            segment = segments.count - 1
            if s < start {
                along = min(1, max(0, (s - prevEnd) / max(1, start - prevEnd)))
                content = s - consumed
            } else {
                along = 1
                carve = min(1, (s - start) / carveLength)
                content = logoAt
            }
        }
        return State(content: content, segment: segment, along: along, carve: carve, beats: beats, pinned: pinned,
                     hold: s - content)
    }

    func point(_ st: State) -> CGPoint {
        let seg = segments[st.segment]
        return seg.path.trimmedPath(from: 0, to: max(0.0005, st.along)).currentPoint ?? .zero
    }

    /// Where a section's middle is on screen: -1 at the top, 0 centered, 1 at the bottom. Drives the 3D tilt.
    func depth(_ i: Int, _ st: State) -> CGFloat {
        let mid = tops[i] + heights[i] / 2 - st.content
        return max(-1.5, min(1.5, (mid - height * 0.5) / (height * 0.5)))
    }
}

// MARK: - The page

private struct StoryCanvas: View {
    let layout: StoryLayout
    let state: StoryLayout.State
    @Binding var heights: [CGFloat]

    private static let dash: [CGFloat] = [0.1, 22]

    var body: some View {
        let l = layout
        ZStack(alignment: .topLeading) {
            hero
            ForEach(0..<StoryLayout.count, id: \.self) { i in
                beat(i)
            }
            // The finish stamps hold still in the middle of the screen, over everything, and fade out of
            // focus as their section moves on rather than sliding away with it.
            ForEach(0..<2, id: \.self) { i in
                let d = l.depth(i, state)
                stamp(i)
                    .opacity(Double(max(0, 1 - max(0, abs(d) - 0.2) * 3)))
                    .blur(radius: max(0, abs(d) - 0.12) * 24)
                    .position(x: l.width / 2, y: state.content + l.height * 0.5)
                    .allowsHitTesting(false)
            }
            line
                .opacity(Double(1 - min(1, state.carve * 1.6)))
            l.logo.trimmedPath(from: 0, to: state.carve)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 100 * l.logoScale, lineCap: .round, lineJoin: .round))
            bead
                .position(l.point(state))
                .opacity(state.carve > 0 ? 0 : 1)
            ending
        }
        // Pinned sections and the logo hold still while the scroll drives them.
        .offset(y: state.hold)
    }

    /// Dots ahead in light gray, dots behind in ink. Each piece keeps the dash rhythm of the whole line.
    private var line: some View {
        let l = layout
        return ZStack(alignment: .topLeading) {
            ForEach(l.segments.indices, id: \.self) { i in
                let seg = l.segments[i]
                let style = StrokeStyle(lineWidth: 9, lineCap: .round, dash: Self.dash, dashPhase: seg.start.truncatingRemainder(dividingBy: 22.1))
                seg.path.stroke(Theme.line, style: style)
                if i < state.segment || (i == state.segment && state.along > 0) {
                    seg.path.trimmedPath(from: 0, to: i < state.segment ? 1 : state.along).stroke(Theme.ink, style: style)
                }
            }
        }
    }

    /// The traveling point: a glossy bead with a soft contact shadow.
    private var bead: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0x5A5A5E), Theme.ink], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 12))
            .overlay(Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5).offset(x: -3, y: -3).blur(radius: 0.5))
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
            .background(Circle().fill(Theme.ink.opacity(0.1)).frame(width: 38, height: 38))
    }

    private var hero: some View {
        let d = max(0, state.content / (layout.height * 0.5))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Prodline").eyebrow()
            Text("Side projects die in a drawer.").display(44, 800).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Prodline gets yours out the door. Scroll to see how.")
                .font(.ui(19)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(width: layout.width, alignment: .leading)
        .offset(x: -min(1, d) * min(1, d) * layout.width)
        .blur(radius: min(1, d) * 6)
        .opacity(Double(1 - min(1, d * 0.9)))
        .offset(y: layout.height * 0.16)
    }

    // MARK: Sections

    private struct Copy { let title: String; let body: String }
    private static let copy = [
        Copy(title: "Build in short bursts", body: "Two weeks, a few checkpoints, and suddenly your project has a plot. The drawer will miss it."),
        Copy(title: "Set your rhythm", body: "Long builds, quick sprints, checkpoints on Tuesdays. Prodline works the way you do, even if that's weird."),
        Copy(title: "Show up every day", body: "One little tick a day keeps the flame happy. It's the lowest-maintenance pet you'll ever own."),
        Copy(title: "You'll finish early", body: "Turns out ticking things off is weirdly fun. Don't be surprised if you beat your own deadline."),
        Copy(title: "Watch it land", body: "Sales, visits and downloads show up on their own. Refreshing five dashboards is now a hobby, not a job."),
        Copy(title: "Then make the call", body: "Keep it, pivot it or let it go. Whatever you pick, you shipped a thing. That's more than most."),
    ]

    private func beat(_ i: Int) -> some View {
        let l = layout
        let left = l.leftLane[i]
        let d = l.depth(i, state)
        let ad = Double(min(1, abs(d)))
        // Sections slide in and out on the side away from the line, so they never cross it.
        let side: CGFloat = left ? 1 : -1
        let slide = { (k: CGFloat) -> CGFloat in
            let t = min(1, max(0, k))
            return t * t * l.width * 1.1
        }
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.copy[i].title).display(32, 800).foregroundStyle(Theme.ink)
                Text(Self.copy[i].body).font(.ui(17)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(x: side * slide(abs(d) - 0.15))
            .rotation3DEffect(.degrees(Double(side * min(1, max(0, abs(d) - 0.15)) * 30)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            visual(i, p: state.beats[i])
                .frame(maxWidth: .infinity)
                // The scene trails the copy: in a beat later, out a beat later.
                .offset(x: side * slide(d > 0 ? abs(d) - 0.02 : abs(d) - 0.32))
                .rotation3DEffect(.degrees(Double(side * min(1, max(0, d > 0 ? abs(d) - 0.02 : abs(d) - 0.32)) * 30)),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        // Clear of the line on its side, the usual margin on the other.
        .padding(.leading, left ? 76 : 24)
        .padding(.trailing, left ? 24 : 76)
        .frame(width: l.width, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            if abs(heights[i] - h) > 1 { heights[i] = h }
        }
        .scaleEffect(1 - ad * 0.08)
        // Out of focus away from the middle, sharp while it plays.
        .blur(radius: max(0, abs(d) - 0.4) * 6)
        .opacity(Double(max(0, 1 - max(0, abs(d) - 0.7) * 1.4)))
        .offset(y: l.tops[i])
    }

    /// "+10 XP" once the goals are ticked, "Dialed in!" once the schedule settles.
    @ViewBuilder
    private func stamp(_ i: Int) -> some View {
        let p = state.beats[i]
        switch i {
        case 0:
            SpelledStamp(text: "+10 XP", accent: Accent(hex: 0xFFC800), size: 76, on: p >= 0.5,
                         confetti: [0xFFC800, 0xFFD94D, 0xE5A500, 0xFFF0A0])
        case 1:
            SpelledStamp(text: "Dialed in!", accent: Accent(hex: 0x58CC02), size: 68, on: p >= 0.62,
                         confetti: [0x58CC02, 0x89E219, 0x46A302, 0xB8F28B])
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func visual(_ i: Int, p: CGFloat) -> some View {
        switch i {
        case 0: BuildBeat(p: p)
        case 1: RhythmBeat(p: p)
        case 2: StreakBeat(p: p)
        case 3: ShipBeat(p: p)
        case 4: NumbersBeat(p: p)
        default: VerdictBeat(p: p)
        }
    }

    private var ending: some View {
        let l = layout
        let shown = state.carve >= 0.98
        return VStack(spacing: 8) {
            Text("Prodline").display(52, 800).foregroundStyle(Theme.ink)
            Text("Ship a project every cycle, watch its numbers come in, and keep the streak going.")
                .font(.ui(17)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(width: l.width)
        .offset(y: l.logoCenter.y + 70)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: shown)
    }
}

// MARK: - The scenes

/// A white card with a solid edge underneath, the chunky 3D look of the app's buttons.
private extension View {
    func chunkySlab(radius: CGFloat, edge: Color = Theme.line, depth: CGFloat = 7, pressed: Bool = false) -> some View {
        background {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(edge).offset(y: pressed ? depth / 2 : depth)
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card)
            }
        }
        .padding(.bottom, depth)
    }
}

/// The project card and its checkpoint; the goals tick one by one.
private struct BuildBeat: View {
    let p: CGFloat
    private static let cover = DemoData.projects.first { $0.name == "Side Shop" }?.cover

    var body: some View {
        let done = [0.15, 0.3, 0.45].map { p >= $0 }
        VStack(spacing: 20) {
            ProjectCardFace(name: "Side Shop", initial: "S", accent: Accent(hex: 0x3A3A3C), cover: Self.cover,
                            cornerLabel: "Day", cornerValue: "12", footnote: "Building · 2d left")
                .frame(width: 150)
                // The card as a solid object: a thick green edge underneath.
                .background {
                    RoundedRectangle(cornerRadius: 30 * 150 / 260, style: .continuous).fill(Color(hex: 0x161618)).offset(y: 8)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 14)
            VStack(alignment: .leading, spacing: 11) {
                Text("Checkpoint 2 · \(done.filter { $0 }.count)/3 goals").font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
                    .contentTransition(.numericText())
                ForEach(Array(["Stripe checkout live", "Product photo grid", "Launch email drafted"].enumerated()), id: \.offset) { n, g in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(done[n] ? Color(hex: 0x46A302) : Theme.line).offset(y: 2.5)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(done[n] ? Color(hex: 0x58CC02) : Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(done[n] ? .clear : Theme.tertiary, lineWidth: 2))
                            if done[n] {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                    .transition(.blurReplace.combined(with: .scale))
                            }
                        }
                        .frame(width: 20, height: 20)
                        .offset(y: done[n] ? 2 : 0)
                        Text(g).font(.ui(15, .medium))
                            .foregroundStyle(done[n] ? Theme.secondary : Theme.ink)
                            .strikethrough(done[n], color: Theme.secondary)
                        Spacer(minLength: 0)
                        Text("+3 XP").font(.display(14, 800)).foregroundStyle(Accent.sale.text)
                            .opacity(done[n] ? 1 : 0)
                            .blur(radius: done[n] ? 0 : 6)
                            .offset(y: done[n] ? 0 : 10)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chunkySlab(radius: 22)
            .animation(.spring(response: 0.38, dampingFraction: 0.65), value: done)
        }
    }
}

/// The app's own schedule editor, played by the scroll: the sliders slide, the checkpoint days switch,
/// and the overlap preview reflows with them, exactly like setting it up by hand.
struct RhythmBeat: View {
    let p: CGFloat

    private static let days: [(Int, String)] = [(2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa"), (1, "Su")]

    /// Build / observe / cadence as the scroll moves, landing on the defaults (2 weeks, 4 weeks, every 2 weeks).
    static func values(_ p: CGFloat) -> (build: Int, observe: Int, every: Int) {
        func key(_ stops: [(CGFloat, CGFloat)]) -> Int {
            if p <= stops[0].0 { return Int(stops[0].1) }
            for (a, b) in zip(stops, stops.dropFirst()) where p <= b.0 {
                let f = (p - a.0) / (b.0 - a.0)
                let e = f < 0.5 ? 2 * f * f : 1 - pow(-2 * f + 2, 2) / 2
                return Int((a.1 + (b.1 - a.1) * e).rounded())
            }
            return Int(stops[stops.count - 1].1)
        }
        return (key([(0.04, 14), (0.2, 7), (0.38, 21), (0.56, 14)]),
                key([(0.12, 28), (0.32, 56), (0.56, 28)]),
                key([(0.22, 14), (0.4, 7), (0.58, 14)]))
    }

    static func stage(_ p: CGFloat) -> Int { p < 0.2 ? 0 : p < 0.38 ? 1 : p < 0.56 ? 2 : 3 }

    var body: some View {
        let v = Self.values(p)
        let checkpointDays: Set<Int> = [[2, 6], [3, 5], [2, 4, 6], [2, 6]][Self.stage(p)].reduce(into: []) { $0.insert($1) }
        VStack(alignment: .leading, spacing: 16) {
            row("Build phase", v.build.durationText) { ChunkySlider(value: .constant(v.build), range: 3...42) }
            row("Observe phase", v.observe.durationText) { ChunkySlider(value: .constant(v.observe), range: 7...90) }
            row("New project every", v.every.durationText) { ChunkySlider(value: .constant(v.every), range: 3...42) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Checkpoint days").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 3) {
                    ForEach(Self.days, id: \.0) { wd, label in
                        DayChip(title: label, isOn: checkpointDays.contains(wd))
                            .frame(maxWidth: .infinity)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: Self.stage(p))
            }
            SchemePreview(build: v.build, observe: v.observe, every: v.every)
        }
        .padding(14)
        .chunkySlab(radius: 22)
        .environment(\.accent, .neutral)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: v.build * 10_000 + v.observe * 100 + v.every)
        .allowsHitTesting(false)
    }

    /// The app's weekday chip, a size down so all seven fit beside the line.
    private struct DayChip: View {
        let title: String
        let isOn: Bool

        var body: some View {
            Text(title)
                .font(.ui(13, .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? .white : Theme.inkSoft)
                .frame(width: 35, height: 35)
                .background(Circle().fill(isOn ? Theme.ink : .white))
                .overlay(Circle().strokeBorder(isOn ? .clear : Theme.line, lineWidth: 1.5))
                .scaleEffect(isOn ? 1.06 : 1)
        }
    }

    private func row<C: View>(_ title: String, _ value: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).display(19, 700).foregroundStyle(Theme.ink).contentTransition(.numericText())
            }
            content()
        }
    }
}

/// Sparks fly in and feed the ember, which swells a little with each; with the last one it catches.
private struct StreakBeat: View {
    let p: CGFloat

    static let sparks = 14
    /// When spark `i` sets off and lands (as scene progress), all landing before the flame catches at 0.55.
    static func window(_ i: Int) -> (CGFloat, CGFloat) {
        let start = 0.02 + CGFloat(i) / CGFloat(sparks) * 0.36
        return (start, start + 0.16)
    }
    static func arrived(_ p: CGFloat) -> Int { (0..<sparks).filter { p >= window($0).1 }.count }

    var body: some View {
        let lit = p >= 0.55
        let fed = Double(Self.arrived(p)) / Double(Self.sparks)
        VStack(spacing: 14) {
            BurningFlame(grow: lit ? 1 : 0.3 + 0.12 * fed, bright: lit ? 1 : 0.15 * fed, width: 110, glow: 0.35)
                .frame(height: 150, alignment: .bottom)
                .animation(.spring(response: 0.6, dampingFraction: 0.55), value: lit)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fed)
                // Sparks drift in from all sides and feed the ember until it catches.
                .background { IgniteSparks(p: p).allowsHitTesting(false) }
                .overlay { SectionBurst(fire: lit, style: .sparks, colors: [0xFF9600, 0xFFC800, 0xFF4B1F, 0xFFE04A]) }
            VStack(spacing: 0) {
                ExtrudedText(text: lit ? "3" : "2", size: 48, accent: lit ? Accent(hex: 0xFF9600) : Accent(hex: 0xC7C7CC))
                    .contentTransition(.numericText())
                Text("DAY STREAK").font(.ui(12, .bold)).tracking(2).foregroundStyle(Theme.secondary)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: lit)
        }
    }
}

/// The sparks that light the streak flame, placed by the scroll: each one fades in out at the edge, then
/// curves in to the base of the flame trailing a short tail. They twinkle on their own while you hold still.
private struct IgniteSparks: View {
    let p: CGFloat

    private static func r(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 41.37 + Double(k) * 12.91) * 43758.5453
        return x - x.rounded(.down)
    }

    var body: some View {
        TimelineView(.animation(paused: p <= 0 || p >= 0.6)) { tl in
            let time = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(ctx, size: size, time: time) }
        }
        .frame(width: 420, height: 320)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, time: Double) {
        let target = CGPoint(x: size.width / 2, y: size.height / 2 + 50)
        for i in 0..<StreakBeat.sparks {
            let (a, b) = StreakBeat.window(i)
            let u = (p - a) / (b - a)
            guard u > -0.15, u < 1 else { continue }
            // From the left and right, level with the flame or a little below, never from above (the copy).
            let ang = (i % 2 == 0 ? Double.pi : 0) + (i % 2 == 0 ? -1 : 1) * (Self.r(i, 1) - 0.25) * 0.9
            let dist = 140 + Self.r(i, 2) * 50
            let from = CGPoint(x: target.x + cos(ang) * dist, y: target.y + sin(ang) * dist * 0.6)
            let ctrl = CGPoint(x: (from.x + target.x) / 2, y: from.y - 30 - Self.r(i, 3) * 40)
            func at(_ k: CGFloat) -> CGPoint {
                let t = min(1, max(0, k))
                let e = t * t
                let v = 1 - e
                let x: CGFloat = v * v * from.x + 2 * v * e * ctrl.x + e * e * target.x
                let y: CGFloat = v * v * from.y + 2 * v * e * ctrl.y + e * e * target.y
                return CGPoint(x: x, y: y)
            }
            let twinkle = 0.75 + 0.25 * sin(time * 14 + Double(i))
            let head = at(u)
            var g = ctx
            // Fading in at the edge before setting off.
            g.opacity = u < 0 ? (u + 0.15) / 0.15 : 1
            if u > 0 {
                var tail = Path()
                tail.move(to: at(u - 0.14))
                tail.addLine(to: head)
                g.stroke(tail, with: .color(Color(hex: 0xFFB000).opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            let rad = 4 * twinkle
            var glow = g
            glow.addFilter(.blur(radius: 5))
            glow.fill(Path(ellipseIn: CGRect(x: head.x - rad * 2.2, y: head.y - rad * 2.2, width: rad * 4.4, height: rad * 4.4)),
                      with: .color(Color(hex: 0xFF9600).opacity(0.6)))
            g.fill(Path(ellipseIn: CGRect(x: head.x - rad, y: head.y - rad, width: rad * 2, height: rad * 2)),
                   with: .color(Color(hex: 0xFFE04A)))
        }
    }
}

/// The days tick up with the scroll, the number growing each day. On day 7 the ship button rises in and
/// gets pressed, and the build ships a week early in fireworks and confetti.
struct ShipBeat: View {
    let p: CGFloat

    static func day(_ p: CGFloat) -> Int { 1 + Int(min(1, max(0, p / 0.55)) * 6) }
    static let appears: CGFloat = 0.6, press: CGFloat = 0.72, ships: CGFloat = 0.8

    var body: some View {
        let day = Self.day(p)
        let pressed = p >= Self.press && p < Self.ships
        let shipped = p >= Self.ships
        let button = p >= Self.appears
        let green = Accent(hex: 0x58CC02)
        let grow = CGFloat(day - 1) / 6
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    ExtrudedText(text: "\(day)", size: 110, accent: shipped ? green : .neutral)
                        .id(day)
                        .transition(.blurReplace.combined(with: .scale(0.7, anchor: .bottom)))
                }
                .scaleEffect(0.42 + 0.58 * grow, anchor: .bottom)
                .frame(height: 132, alignment: .bottom)
                ZStack {
                    Text(shipped ? "days early" : "Day \(day) of 14")
                        .font(.display(22, 800))
                        .foregroundStyle(shipped ? green.text : Theme.secondary)
                        .id(shipped ? 0 : day)
                        .transition(.blurReplace)
                }
            }
            .overlay { SectionBurst(fire: shipped, style: .firework) }
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(green.dark).offset(y: 6)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(green.base)
                    .overlay(Text(shipped ? "Shipped" : "Let's ship").font(.display(18, 700)).tracking(2.4).textCase(.uppercase)
                        .foregroundStyle(.white).contentTransition(.interpolate))
                    .offset(y: pressed ? 6 : 0)
            }
            .frame(width: 230, height: 56)
            .padding(.bottom, 6)
            .scaleEffect(button ? 1 : 0.7)
            .blur(radius: button ? 0 : 10)
            .opacity(button ? 1 : 0)
            .offset(y: button ? 0 : 24)
            .overlay { SectionBurst(fire: shipped, style: .confetti) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: day)
        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: button)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: shipped)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
    }
}

/// Numbers count up with the scroll; the services they come from pop in underneath.
private struct NumbersBeat: View {
    let p: CGFloat

    var body: some View {
        let k = min(1, max(0, (p - 0.1) / 0.7))
        let e = 1 - pow(1 - k, 3)
        VStack(spacing: 22) {
            HStack(alignment: .bottom, spacing: 18) {
                stat(MetricKey.count(1240 * e), "visits", 0x58CC02, big: true)
                stat("$" + MetricKey.count(612 * e), "revenue", 0xFFC800, big: false)
                stat(MetricKey.count(312 * e), "downloads", 0xA35CFF, big: false)
            }
            .blur(radius: (1 - min(1, k * 4)) * 6)
            .overlay { SectionBurst(fire: k >= 1, style: .sparks, colors: [0x58CC02, 0xFFC800, 0xA35CFF]) }
            HStack(spacing: 10) {
                ForEach(Array([IntegrationKind.appStore, .stripe, .revenueCat, .plausible, .youtube].enumerated()), id: \.offset) { n, kind in
                    let on = p >= 0.3 + Double(n) * 0.1
                    IntegrationIcon(kind: kind, size: 38)
                        .background(RoundedRectangle(cornerRadius: 11.4, style: .continuous).fill(Color.black.opacity(0.18)).offset(y: 4))
                        .scaleEffect(on ? 1 : 0.4)
                        .rotation3DEffect(.degrees(on ? 0 : 80), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                        .blur(radius: on ? 0 : 8)
                        .opacity(on ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: on)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ hex: Int, big: Bool) -> some View {
        VStack(spacing: 2) {
            ExtrudedText(text: value, size: big ? 40 : 30, accent: Accent(hex: hex))
            Text(label).font(.ui(12, .semibold)).foregroundStyle(Theme.secondary)
        }
    }
}

/// Kill, pivot, keep: the choice moves along with the scroll and lands on keep.
private struct VerdictBeat: View {
    let p: CGFloat

    var body: some View {
        let pick: Verdict? = p < 0.15 ? nil : p < 0.4 ? .kill : p < 0.65 ? .pivot : .keep
        HStack(spacing: 10) {
            ForEach([Verdict.keep, .pivot, .kill]) { v in
                let on = pick == v
                let a = Accent(hex: v.hex)
                VStack(spacing: 8) {
                    Image(systemName: v.symbol).font(.system(size: 22, weight: .bold))
                        .foregroundStyle(on ? a.on : a.base)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(on ? a.base : a.tint))
                    Text(v.title).font(.display(17, 750)).foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .chunkySlab(radius: 20, edge: on ? a.dark : Theme.line, pressed: on)
                .offset(y: on ? 3 : 0)
                .scaleEffect(on && v == .keep ? 1.06 : 1)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.6), value: pick)
        .overlay(alignment: .leading) {
            // Keep lands on the left tile: confetti from there.
            GeometryReader { g in
                SectionBurst(fire: pick == .keep, style: .confetti)
                    .position(x: (g.size.width - 20) / 6, y: g.size.height / 2)
            }
        }
    }
}

// MARK: - Finishing bursts

/// A scene's finished state: big angled 3D lettering that types itself out letter by letter, each letter
/// dropping in out of a blur, with a dark drop shadow lifting it off the scene. Confetti once it's spelled.
private struct SpelledStamp: View {
    let text: String
    let accent: Accent
    var size: CGFloat = 64
    let on: Bool
    var confetti: [Int]
    @State private var shown = 0
    @State private var typing: Task<Void, Never>?

    var body: some View {
        let letters = Array(text)
        HStack(spacing: 0) {
            ForEach(letters.indices, id: \.self) { i in
                let visible = i < shown
                StampLetter(text: String(letters[i]), size: size, accent: accent)
                    .opacity(visible ? 1 : 0)
                    .scaleEffect(visible ? 1 : 1.9)
                    .blur(radius: visible ? 0 : 10)
                    .offset(y: visible ? 0 : -24)
                    .animation(.spring(response: 0.32, dampingFraction: 0.55), value: visible)
            }
        }
        .fixedSize()
        // A dark drop shadow lifts it off the page.
        .shadow(color: .black.opacity(0.35), radius: 1, x: 2, y: 4)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 6, y: 16)
        .rotation3DEffect(.degrees(26), axis: (x: 1, y: -0.45, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(-8))
        .overlay { SectionBurst(fire: shown == letters.count, style: .confetti, colors: confetti) }
        .allowsHitTesting(false)
        .onChange(of: on, initial: true) { _, on in
            typing?.cancel()
            guard on else { shown = 0; return }
            typing = Task { @MainActor in
                for i in 1...letters.count {
                    try? await Task.sleep(for: .milliseconds(75))
                    if Task.isCancelled { return }
                    shown = i
                    if letters[i - 1] != " " { Haptics.select() }
                }
                Haptics.success()
            }
        }
    }
}

/// One letter of a stamp as a solid object: a deep extruded side shading darker toward the back, a face
/// that's lighter at the top, and a glossy highlight across its upper half, like the chunky buttons.
private struct StampLetter: View {
    let text: String
    let size: CGFloat
    let accent: Accent

    private var depth: Int { max(6, Int(size / 7)) }

    var body: some View {
        ZStack {
            ForEach((1...depth).reversed(), id: \.self) { i in
                face.foregroundStyle(accent.dark)
                    .brightness(-0.18 * Double(i) / Double(depth))
                    .offset(x: CGFloat(i) * 0.5, y: CGFloat(i) * 1.0)
            }
            face.foregroundStyle(LinearGradient(colors: [accent.base.mix(with: .white, by: 0.35), accent.base],
                                                startPoint: .top, endPoint: .bottom))
            // Gloss on the top half of the face.
            face.foregroundStyle(LinearGradient(stops: [.init(color: .white.opacity(0.55), location: 0),
                                                        .init(color: .white.opacity(0.15), location: 0.45),
                                                        .init(color: .clear, location: 0.5)],
                                                startPoint: .top, endPoint: .bottom))
        }
        .padding(.bottom, CGFloat(depth))
        .drawingGroup()
    }

    private var face: some View {
        Text(text).display(size, 900).lineLimit(1).fixedSize()
    }
}

/// A one-shot burst played when a section's scene completes: confetti, sparks, or fireworks. Drawn on a
/// canvas larger than its host, so it spills out over the page.
struct SectionBurst: View {
    enum Style { case confetti, sparks, firework }
    var fire: Bool
    var style: Style
    var colors: [Int] = [0x58CC02, 0xFFC800, 0xFF4B4B, 0x1CB0F6, 0xCE82FF, 0xFF9600]
    @State private var start: Date?

    private static let life: Double = 2.2

    var body: some View {
        let running = start.map { Date().timeIntervalSince($0) < Self.life } ?? false
        TimelineView(.animation(paused: !running)) { tl in
            Canvas { ctx, size in
                guard let start else { return }
                let t = tl.date.timeIntervalSince(start)
                guard t >= 0, t < Self.life else { return }
                draw(&ctx, c: CGPoint(x: size.width / 2, y: size.height / 2), t: t)
            }
        }
        .frame(width: 560, height: 640)
        .allowsHitTesting(false)
        .onChange(of: fire) { _, on in if on { start = .now } }
    }

    /// Stable pseudo-random numbers per particle, so every burst looks the same frame to frame.
    private static func r(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    private func color(_ i: Int) -> Color { Color(hex: colors[i % colors.count]) }

    private func draw(_ ctx: inout GraphicsContext, c: CGPoint, t: Double) {
        // A quick soft shockwave ring under every burst.
        if t < 0.4 {
            let rad = 24 + t * 360
            var ring = ctx
            ring.opacity = (1 - t / 0.4) * 0.5
            ring.addFilter(.blur(radius: 3))
            ring.stroke(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)),
                        with: .color(color(0)), lineWidth: 6)
        }
        switch style {
        case .confetti:
            for i in 0..<70 {
                let a = -Double.pi / 2 + (Self.r(i, 1) - 0.5) * 2.4
                let v = 360 + Self.r(i, 2) * 520
                let travel = v * (1 - exp(-2.8 * t)) / 2.8
                let x = c.x + cos(a) * travel
                let y = c.y + sin(a) * travel + 140 * t * t
                var p = ctx
                p.opacity = max(0, min(1, (Self.life - t) / 0.6))
                p.translateBy(x: x, y: y)
                p.rotate(by: .radians((Self.r(i, 3) - 0.5) * 16 * t + Self.r(i, 4) * 6))
                p.scaleBy(x: cos(t * (5 + Self.r(i, 5) * 8)), y: 1)
                let w = 7 + Self.r(i, 6) * 5, h = w * 0.55
                p.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 1.5), with: .color(color(i)))
            }
        case .sparks:
            for i in 0..<56 {
                let a = Self.r(i, 1) * 2 * .pi
                let v = 200 + Self.r(i, 2) * 380
                let travel = v * (1 - exp(-3.2 * t)) / 3.2
                let x = c.x + cos(a) * travel
                let y = c.y + sin(a) * travel + 90 * t * t
                let k = max(0, 1 - t / (0.8 + Self.r(i, 3) * 0.6))
                let rad = (1.6 + Self.r(i, 4) * 3) * k
                guard rad > 0.2 else { continue }
                var p = ctx
                p.opacity = k
                p.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(color(i)))
            }
        case .firework:
            let shells: [(CGFloat, CGFloat, Double)] = [(-95, -70, 0), (90, -105, 0.22), (0, -175, 0.44)]
            for (n, shell) in shells.enumerated() {
                let tt = t - shell.2
                guard tt > 0 else { continue }
                let o = CGPoint(x: c.x + shell.0, y: c.y + shell.1)
                let fade = max(0, 1 - tt / 1.3)
                func pos(_ a: Double, _ v: Double, _ s: Double) -> CGPoint {
                    let s = max(0, s)
                    let travel = v * (1 - exp(-2.4 * s)) / 2.4
                    return CGPoint(x: o.x + cos(a) * travel, y: o.y + sin(a) * travel + 70 * s * s)
                }
                for i in 0..<26 {
                    let a = Double(i) / 26 * 2 * .pi + Double(n)
                    let v = 230 + Self.r(i + n * 40, 2) * 60
                    var trail = Path()
                    trail.move(to: pos(a, v, tt - 0.09))
                    trail.addLine(to: pos(a, v, tt))
                    var p = ctx
                    p.opacity = fade
                    p.stroke(trail, with: .color(color(n * 2 + (i % 2))), style: StrokeStyle(lineWidth: 3.5 * (0.4 + 0.6 * fade), lineCap: .round))
                }
            }
        }
    }
}
