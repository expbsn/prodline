import SwiftUI

/// The first onboarding screen, told on scroll: a point travels down a winding dotted line (the stretch behind
/// it turns solid), and each part of the app comes alive as the point reaches it — goals ticking, the streak
/// flame catching, shipping early, numbers coming in, keep / pivot / kill. At the bottom the line loops under
/// the logo and carves the "p" from the stem up, like the launch animation; the page holds still meanwhile.
struct StoryOnboarding: View {
    var onFinish: () -> Void
    @State private var offset: CGFloat = 0
    @State private var layout: StoryLayout?
    @State private var lastBeat = -1
    @State private var carved = false

    var body: some View {
        GeometryReader { geo in
            let l = layout ?? StoryLayout(width: geo.size.width, height: geo.size.height)
            let state = l.state(offset: offset)
            ScrollView(showsIndicators: false) {
                StoryCanvas(layout: l, state: state)
                    .frame(width: l.width, height: l.contentHeight, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in
                offset = v
            }
            .onAppear { if layout?.size != geo.size { layout = StoryLayout(width: geo.size.width, height: geo.size.height) } }
            .onChange(of: geo.size) { layout = StoryLayout(width: geo.size.width, height: geo.size.height) }
            .onChange(of: state.beat) { _, beat in
                // A light tap for every beat the point passes, a success when the logo is complete.
                guard beat > lastBeat else { lastBeat = beat; return }
                lastBeat = beat
                Haptics.soft()
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

// MARK: - Geometry

/// Where everything sits on the page, the winding path, and how scrolling maps onto it. Built once per size.
struct StoryLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    var size: CGSize { CGSize(width: width, height: height) }

    /// Tops of the five beats, and which lane (side) the line runs down beside each.
    let tops: [CGFloat]
    let leftLane: [Bool]
    let beatHeight: CGFloat
    let logoCenter: CGPoint
    let logoScale: CGFloat
    /// The dotted line (start → beats → under the logo → up to the stem) and the logo stroke.
    let line: Path
    let logo: Path
    private let lineSamples: [CGPoint]
    private let lineOffsets: [CGFloat]
    private let logoSamples: [CGPoint]
    let lineEndOffset: CGFloat
    let carveScroll: CGFloat
    let contentHeight: CGFloat
    /// Where on screen the point rides while it travels.
    static let anchor: CGFloat = 0.55

    static func == (a: StoryLayout, b: StoryLayout) -> Bool { a.size == b.size }

    init(width w: CGFloat, height vh: CGFloat) {
        width = w
        height = vh
        beatHeight = vh * 0.8
        tops = (0..<5).map { vh * 0.75 + CGFloat($0) * vh * 0.8 }
        leftLane = (0..<5).map { $0 % 2 == 0 }
        let lane = { (left: Bool) -> CGFloat in left ? 32 : w - 32 }

        // The logo, as LogoGeometry draws it (1024-unit icon space), 170 points wide.
        logoScale = 170 / 850
        let lastBottom = tops[4] + vh * 0.66
        logoCenter = CGPoint(x: w / 2 + 6, y: lastBottom + vh * 0.3)
        let k = logoScale, c = logoCenter
        func L(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + (x - 600) * k, y: c.y + (y - 410) * k) }

        var p = Path()
        let start = CGPoint(x: w / 2, y: vh * 0.5)
        p.move(to: start)
        var prev = start
        func curve(to q: CGPoint, bend: CGFloat = 0.5) {
            let dy = q.y - prev.y
            p.addCurve(to: q, control1: CGPoint(x: prev.x, y: prev.y + dy * bend), control2: CGPoint(x: q.x, y: q.y - dy * bend))
            prev = q
        }
        for i in 0..<5 {
            let x = lane(leftLane[i])
            curve(to: CGPoint(x: x, y: tops[i] + vh * 0.02))
            p.addLine(to: CGPoint(x: x, y: tops[i] + vh * 0.66))
            prev = CGPoint(x: x, y: tops[i] + vh * 0.66)
        }
        // Swing round under the logo and come straight up into the bottom of the stem, as in the launch animation.
        let stemBottom = L(490, 630)
        let below = CGPoint(x: stemBottom.x, y: stemBottom.y + vh * 0.12)
        p.addCurve(to: below, control1: CGPoint(x: prev.x, y: below.y + vh * 0.06), control2: CGPoint(x: below.x, y: below.y + vh * 0.06))
        p.addLine(to: stemBottom)
        line = p

        var lg = Path()
        lg.move(to: L(490, 630))
        lg.addLine(to: L(490, 390))
        lg.addCurve(to: L(672, 190), control1: L(490, 250), control2: L(552, 190))
        lg.addCurve(to: L(856, 342), control1: L(792, 190), control2: L(856, 262))
        lg.addCurve(to: L(700, 490), control1: L(856, 430), control2: L(792, 490))
        lg.addLine(to: L(402, 490))
        logo = lg

        // Sample both paths so scrolling can find the point quickly.
        let n = 600
        lineSamples = (0...n).map { i in i == 0 ? start : p.trimmedPath(from: 0, to: CGFloat(i) / CGFloat(n)).currentPoint ?? start }
        logoSamples = (0...200).map { i in i == 0 ? L(490, 630) : lg.trimmedPath(from: 0, to: CGFloat(i) / 200).currentPoint ?? L(490, 630) }
        // How far the page has to scroll for the point to reach each sample (it rides at `anchor` on screen).
        var offs: [CGFloat] = []
        var m = -CGFloat.infinity
        for s in lineSamples {
            m = max(m, s.y - vh * Self.anchor)
            offs.append(m)
        }
        lineOffsets = offs
        lineEndOffset = offs.last ?? 0
        carveScroll = vh * 0.5
        contentHeight = lineEndOffset + carveScroll + vh
    }

    struct State {
        /// 0…1 along the dotted line, then 0…1 along the logo.
        var travel: CGFloat
        var carve: CGFloat
        var point: CGPoint
        /// The page holds still while the logo is carved.
        var hold: CGFloat
        /// How far each beat has come (0…1), driven by where the point is.
        var beats: [CGFloat]
        var beat: Int
        var heroFade: CGFloat
    }

    func state(offset: CGFloat) -> State {
        let travel: CGFloat
        let carve: CGFloat
        let point: CGPoint
        if offset < lineEndOffset {
            // The last sample the page has scrolled past, then interpolate to the next.
            var lo = 0, hi = lineOffsets.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineOffsets[mid] <= offset { lo = mid } else { hi = mid - 1 }
            }
            let next = min(lo + 1, lineOffsets.count - 1)
            let span = lineOffsets[next] - lineOffsets[lo]
            let f = span > 0 ? (offset - lineOffsets[lo]) / span : 0
            let a = lineSamples[lo], b = lineSamples[next]
            travel = (CGFloat(lo) + f) / CGFloat(lineSamples.count - 1)
            point = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            carve = 0
        } else {
            travel = 1
            carve = min(1, (offset - lineEndOffset) / carveScroll)
            let i = Int(carve * CGFloat(logoSamples.count - 1))
            point = logoSamples[min(i, logoSamples.count - 1)]
        }
        let ride = offset + height * Self.anchor
        // Each beat plays out while it's around the middle of the screen.
        let beats = tops.map { min(1, max(0, (ride - ($0 + height * 0.14)) / (height * 0.4))) }
        let beat = beats.enumerated().reduce(0) { $0 + ($1.element >= 0.5 ? 1 : 0) } + (carve >= 1 ? 1 : 0)
        return State(travel: travel, carve: carve, point: point, hold: max(0, min(carveScroll, offset - lineEndOffset)),
                     beats: beats, beat: beat, heroFade: max(0, 1 - offset / (height * 0.25)))
    }
}

// MARK: - The page

private struct StoryCanvas: View {
    let layout: StoryLayout
    let state: StoryLayout.State

    var body: some View {
        let l = layout
        ZStack(alignment: .topLeading) {
            hero
            ForEach(0..<5, id: \.self) { i in
                beat(i, progress: state.beats[i])
            }
            // The line: dots ahead in light gray, dots behind in ink, the point riding at its head.
            Group {
                l.line.stroke(Theme.line, style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [0.1, 22]))
                l.line.trimmedPath(from: 0, to: state.travel)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [0.1, 22]))
            }
            // Once the "p" is being carved the line has done its job and fades, leaving just the logo.
            .opacity(Double(1 - min(1, state.carve * 1.6)))
            l.logo.trimmedPath(from: 0, to: state.carve)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 100 * l.logoScale, lineCap: .round, lineJoin: .round))
            Circle().fill(Theme.ink)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.ink.opacity(0.12)).frame(width: 34, height: 34))
                .position(state.point)
                .opacity(state.carve > 0 ? 0 : 1)
            ending
        }
        // While the logo is carved the page holds still.
        .offset(y: state.hold)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prodline").eyebrow()
            Text("Side projects die in a drawer.").display(44, 800).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Prodline gets yours out the door. Scroll to see how.")
                .font(.ui(19)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(width: layout.width, alignment: .leading)
        .offset(y: layout.height * 0.14)
        .overlay(alignment: .top) {
            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.tertiary)
                .offset(y: layout.height * 0.62)
                .opacity(state.heroFade)
        }
    }

    // MARK: Beats

    private struct Copy { let title: String; let body: String }
    private static let copy = [
        Copy(title: "Build in short bursts", body: "Two weeks per project. Checkpoints and goals keep it moving."),
        Copy(title: "Show up every day", body: "One thing ticked a day keeps the flame burning."),
        Copy(title: "Ship it early", body: "Done before the deadline? Ship it and bank the days."),
        Copy(title: "Watch it land", body: "Visits, revenue and downloads, straight from the tools you use."),
        Copy(title: "Then make the call", body: "Keep it, pivot it or kill it. The numbers help you decide."),
    ]

    private func beat(_ i: Int, progress p: CGFloat) -> some View {
        let l = layout
        let left = l.leftLane[i]
        let appear = min(1, p * 3)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.copy[i].title).display(32, 800).foregroundStyle(Theme.ink)
                Text(Self.copy[i].body).font(.ui(17)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appear)
            .offset(y: (1 - appear) * 24)
            visual(i, p: p)
                .frame(maxWidth: .infinity)
        }
        .padding(.leading, left ? 64 : 24)
        .padding(.trailing, left ? 24 : 64)
        .frame(width: l.width, alignment: .leading)
        .offset(y: l.tops[i] + l.beatHeight * 0.06)
    }

    @ViewBuilder
    private func visual(_ i: Int, p: CGFloat) -> some View {
        switch i {
        case 0: BuildBeat(p: p)
        case 1: StreakBeat(p: p)
        case 2: ShipBeat(p: p)
        case 3: NumbersBeat(p: p)
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

// MARK: - The beats

/// Goals tick as the point passes.
private struct BuildBeat: View {
    let p: CGFloat
    private static let cover = DemoData.projects.first { $0.name == "Habit Hero" }?.cover

    var body: some View {
        let done = [0.3, 0.5, 0.7].map { p >= $0 }
        VStack(spacing: 16) {
            ProjectCardFace(name: "Habit Hero", initial: "H", accent: Accent(hex: 0x58CC02), cover: Self.cover,
                            cornerLabel: "Day", cornerValue: "12", footnote: "Building · 2d left")
                .frame(width: 150)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                .scaleEffect(0.85 + 0.15 * min(1, p * 2.5))
            VStack(alignment: .leading, spacing: 11) {
                Text("Checkpoint 2 · \(done.filter { $0 }.count)/3 goals").font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
                ForEach(Array(["Onboarding flow live", "Shareable streak card", "Push reminders"].enumerated()), id: \.offset) { n, g in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(done[n] ? Color(hex: 0x58CC02) : Theme.tertiary, lineWidth: 2)
                            if done[n] {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: 0x58CC02))
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(g).font(.ui(15, .medium))
                            .foregroundStyle(done[n] ? Theme.secondary : Theme.ink)
                            .strikethrough(done[n], color: Theme.secondary)
                        Spacer(minLength: 0)
                        Text("+3 XP").font(.display(14, 800)).foregroundStyle(Accent.sale.text)
                            .opacity(done[n] ? 1 : 0)
                            .offset(y: done[n] ? 0 : 6)
                    }
                }
            }
            .card(padding: 16, radius: 22)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
        }
    }
}

/// The flame grows as the point comes down and catches halfway.
private struct StreakBeat: View {
    let p: CGFloat

    var body: some View {
        let lit = p >= 0.6
        VStack(spacing: 14) {
            BurningFlame(grow: Double(0.06 + 0.3 * min(1, p / 0.6)) + (lit ? 0.64 : 0), bright: lit ? 1 : 0, width: 110)
                .frame(height: 150, alignment: .bottom)
                .animation(.spring(response: 0.6, dampingFraction: 0.55), value: lit)
            VStack(spacing: 0) {
                Text(lit ? "3" : "2").display(44, 850).foregroundStyle(lit ? Theme.flame : Theme.tertiary)
                    .contentTransition(.numericText())
                Text("DAY STREAK").font(.ui(12, .bold)).tracking(2).foregroundStyle(Theme.secondary)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: lit)
        }
    }
}

/// The button sinks in, then "4 days early" tips up.
private struct ShipBeat: View {
    let p: CGFloat

    var body: some View {
        let pressed = p >= 0.35 && p < 0.47
        let shipped = p >= 0.47
        let green = Accent(hex: 0x58CC02)
        VStack(spacing: 22) {
            VStack(spacing: 0) {
                ExtrudedText(text: "4", size: 96, accent: green)
                ExtrudedText(text: "days early", size: 28, accent: green, weight: 800)
            }
            .rotation3DEffect(.degrees(shipped ? 0 : 70), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .scaleEffect(shipped ? 1 : 0.6, anchor: .bottom)
            .opacity(shipped ? 1 : 0)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(green.dark).offset(y: 5)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(green.base)
                    .overlay(Text("Let's ship").font(.display(18, 700)).tracking(2.4).textCase(.uppercase).foregroundStyle(.white))
                    .offset(y: pressed ? 5 : 0)
            }
            .frame(width: 230, height: 56)
            .padding(.bottom, 5)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: shipped)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressed)
    }
}

/// Numbers count up with the scroll; the services they come from line up underneath.
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
            HStack(spacing: 10) {
                ForEach(Array([IntegrationKind.appStore, .stripe, .revenueCat, .plausible, .youtube].enumerated()), id: \.offset) { n, kind in
                    let on = p >= 0.25 + Double(n) * 0.09
                    IntegrationIcon(kind: kind, size: 38)
                        .scaleEffect(on ? 1 : 0.4)
                        .opacity(on ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: on)
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
        let pick: Verdict? = p < 0.2 ? nil : p < 0.4 ? .kill : p < 0.6 ? .pivot : .keep
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
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(on ? a.base : Theme.line, lineWidth: on ? 2.5 : 1.5))
                .scaleEffect(on && v == .keep ? 1.06 : on ? 1.02 : 1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: pick)
    }
}
