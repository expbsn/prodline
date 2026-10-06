import SwiftUI

// MARK: - Chunky button (3D press, colored by the environment accent)

enum ChunkyKind { case accent, neutral, danger }

struct ChunkyButtonStyle: ButtonStyle {
    var kind: ChunkyKind = .accent
    var height: CGFloat = 58
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        ChunkyButtonBody(configuration: configuration, kind: kind, height: height, fullWidth: fullWidth)
    }
}

private struct ChunkyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ChunkyKind
    let height: CGFloat
    let fullWidth: Bool
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var enabled

    private let depth: CGFloat = 5

    var body: some View {
        let pressed = configuration.isPressed
        let (fill, edge, fg, border) = colors
        let radius = height * 0.34
        configuration.label
            .display(height < 48 ? 15 : 19, 700)
            .tracking(height < 48 ? 1.2 : 2.4)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(fg)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 18)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 2)
                }
            }
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(edge)
                    .offset(y: pressed ? 0 : depth)
            }
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.16, dampingFraction: 0.62), value: pressed)
            .onChange(of: pressed) { _, isDown in if isDown { Haptics.tap() } }
    }

    private var colors: (Color, Color, Color, Color?) {
        guard enabled else { return (Theme.line, Color(hex: 0xD1D1D6), Theme.secondary, nil) }
        switch kind {
        case .accent: return (accent.base, accent.dark, accent.on, nil)
        case .neutral: return (.white, Theme.line, Theme.ink, Theme.line)
        case .danger: return (.white, Theme.line, Theme.danger, Theme.line)
        }
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { ChunkyButtonStyle() }
    static func chunky(_ kind: ChunkyKind, height: CGFloat = 58, fullWidth: Bool = true) -> ChunkyButtonStyle {
        ChunkyButtonStyle(kind: kind, height: height, fullWidth: fullWidth)
    }
}

/// Squish + soft haptic for tappable cards and rows.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.soft() } }
    }
}

/// Round icon button used in headers (close, more…).
struct CircleIconButton: View {
    let systemName: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

// MARK: - Surfaces

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 26) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
    }

    func inputField(focused: Bool = false) -> some View {
        self.font(.ui(17, .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? Theme.ink : Theme.line, lineWidth: 2))
    }
}

struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // Trailing content is an overlay so it can never change the header height:
        // titles sit at the same position on every tab.
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow).eyebrow()
            Text(title).display(42, 750).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomTrailing) { trailing.padding(.bottom, 4) }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    init(_ text: String, trailing: String? = nil) { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).display(24, 700).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing { Text(trailing).eyebrow(size: 11) }
        }
    }
}

// MARK: - Chip

struct Chip: View {
    let title: String
    let isOn: Bool
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { action() }
        } label: {
            Text(title)
                .font(.ui(14, .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? accent.on : Theme.inkSoft)
                .padding(.horizontal, 12)
                .frame(minWidth: 40, minHeight: 40)
                .background(Capsule().fill(isOn ? accent.base : .white))
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle(scale: 0.92))
    }
}

// MARK: - Progress

struct ChunkyProgressBar: View {
    var value: Double
    var color: Color? = nil
    var height: CGFloat = 14
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(color ?? accent.base)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.32))
                            .frame(height: height * 0.24)
                            .padding(.horizontal, height * 0.45)
                            .padding(.top, height * 0.2)
                    }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: value)
        }
        .frame(height: height)
    }
}

// MARK: - Slider

struct ChunkySlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var color: Color? = nil
    @Environment(\.accent) private var accent
    @State private var dragging = false
    /// Decided on the first movement: nil = undecided, true = horizontal (slider), false = vertical (page scroll).
    @State private var horizontal: Bool?

    private let knob: CGFloat = 34

    private func set(at x: CGFloat, width w: CGFloat, span: CGFloat) {
        let f = min(max((x - knob / 2) / (w - knob), 0), 1)
        let new = range.lowerBound + Int((f * span).rounded())
        if new != value {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) { value = new }
            Haptics.select()
        }
    }

    var body: some View {
        let tint = color ?? accent.base
        GeometryReader { geo in
            let w = geo.size.width
            let span = CGFloat(range.upperBound - range.lowerBound)
            let frac = span == 0 ? 0 : CGFloat(value - range.lowerBound) / span
            let x = frac * (w - knob)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 14)
                Capsule().fill(tint).frame(width: x + knob / 2, height: 14)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 5))
                    .shadow(color: .black.opacity(dragging ? 0.18 : 0.08), radius: dragging ? 8 : 3, y: 2)
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragging ? 1.18 : 1)
                    .offset(x: x)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            // Simultaneous + axis lock: vertical drags keep scrolling the page and never move the slider.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { g in
                        if horizontal == nil {
                            horizontal = abs(g.translation.width) > abs(g.translation.height)
                        }
                        guard horizontal == true else { return }
                        if !dragging {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { dragging = true }
                            Haptics.soft()
                        }
                        set(at: g.location.x, width: w, span: span)
                    }
                    .onEnded { _ in
                        horizontal = nil
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { dragging = false }
                    }
            )
            .onTapGesture(coordinateSpace: .local) { p in set(at: p.x, width: w, span: span) }
        }
        .frame(height: 44)
    }
}

// MARK: - Celebration

/// Text cut out of a solid block: the face in the accent, the depth in its darker shade (like the chunky buttons).
struct ExtrudedText: View {
    let text: String
    let size: CGFloat
    let accent: Accent
    var weight: CGFloat = 850
    private var depth: Int { max(4, Int(size / 14)) }

    var body: some View {
        ZStack {
            ForEach((1...depth).reversed(), id: \.self) { i in
                face.foregroundStyle(accent.dark).offset(x: CGFloat(i) * 0.45, y: CGFloat(i) * 0.9)
            }
            face.foregroundStyle(accent.base)
        }
        .padding(.bottom, CGFloat(depth) * 0.9)
        .drawingGroup()
    }

    private var face: some View {
        Text(text).display(size, weight).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
    }
}

@Observable
final class CelebrationCenter {
    struct Banner: Equatable { var title: String; var subtitle: String; var accent: Accent }
    /// A project shipped before its launch day: the big "N days early" moment.
    struct ShipMoment: Identifiable, Equatable {
        let id = UUID()
        let daysEarly: Int
        /// The build phase as planned, to judge how early "early" is.
        let plannedDays: Int
        let project: String
        let accent: Accent
        let xp: Int

        /// Share of the planned build that was left over.
        var earlyShare: Double { plannedDays > 0 ? Double(daysEarly) / Double(plannedDays) : 0 }

        /// Three lines from someone who can't quite believe it, more impressed the earlier it is.
        var reactions: [String] {
            let options: [[String]]
            switch earlyShare {
            case 0.5...:
                options = [["Wait.", "Half the time?!", "Are you even human?"],
                           ["Excuse me?", "That fast?!", "Somebody stop this person."]]
            case 0.3..<0.5:
                options = [["Hold up.", "Already finished?", "You're killing it!"],
                           ["No way.", "Done already?", "Okay, show-off."]]
            case 0.15..<0.3:
                options = [["Oh?", "Finished early?", "Look at you go."],
                           ["Hey, hey.", "Ahead of schedule?", "We love to see it."]]
            default:
                options = [["Well, well.", "A little early, huh?", "Every day counts."],
                           ["Psst.", "Did you just beat the clock?", "Smooth."]]
            }
            return options[abs(id.hashValue) % options.count]
        }
    }
    /// What a celebration was for, so several can be summed up in one banner.
    enum Kind { case checkpoint, goals(Int), other }

    var banner: Banner?
    var confetti: (id: UUID, accent: Accent)?
    var ship: ShipMoment?
    /// Today's first progress: the streak flame lights up in the middle of the screen.
    var streakLit: StreakMoment?
    private var pendingStreak: StreakMoment?

    struct StreakMoment: Identifiable, Equatable {
        let id = UUID()
        let days: Int
    }

    /// A full-screen moment is playing; banners wait in line until it's over.
    private var takeover: Bool { ship != nil || streakLit != nil }

    func lightStreak(_ days: Int) {
        let moment = StreakMoment(days: days)
        // Waits for the "while you were away" pass or a ship moment to finish first.
        if collecting != nil || takeover { pendingStreak = moment; return }
        holdBanner()
        withAnimation(.easeOut(duration: 0.35)) { streakLit = moment }
    }

    func endStreak() {
        withAnimation(.easeIn(duration: 0.3)) { streakLit = nil }
        resumeAfterTakeover()
    }

    /// A banner that's up goes back to the front of the line.
    private func holdBanner() {
        guard let b = banner else { return }
        dismissTask?.cancel()
        // Instantly: it usually went up this very moment and shouldn't flash before the takeover.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { banner = nil; confetti = nil }
        queue.insert((b, 2.6, false, {}), at: 0)
    }

    /// Next up after a full-screen moment: a waiting streak flame, else the queued banners.
    private func resumeAfterTakeover() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !self.takeover, self.banner == nil else { return }
            if let s = self.pendingStreak {
                self.pendingStreak = nil
                withAnimation(.easeOut(duration: 0.35)) { self.streakLit = s }
                return
            }
            guard !self.queue.isEmpty else { return }
            let next = self.queue.removeFirst()
            self.present(next.banner, seconds: next.seconds, confetti: next.confetti, haptic: next.haptic)
        }
    }

    /// The ship moment owns the screen: a banner that's up goes back in line and waits with the others.
    func celebrateShip(_ moment: ShipMoment) {
        holdBanner()
        withAnimation(.easeOut(duration: 0.3)) { ship = moment }
    }

    func endShip() {
        withAnimation(.easeIn(duration: 0.3)) { ship = nil }
        resumeAfterTakeover()
    }
    private var dismissTask: Task<Void, Never>?
    /// Banners waiting for the current one to leave (nothing gets overwritten mid-read).
    private var queue: [(banner: Banner, seconds: Double, confetti: Bool, haptic: () -> Void)] = []

    private struct Collected { var title: String; var subtitle: String; var accent: Accent; var confetti: Bool; var xp: Int; var kind: Kind }
    private var collecting: [Collected]?

    func fire(title: String, subtitle: String, accent: Accent = .neutral, confetti showConfetti: Bool = true,
              xp: Int = 0, kind: Kind = .other) {
        if collecting != nil {
            collecting?.append(Collected(title: title, subtitle: subtitle, accent: accent, confetti: showConfetti, xp: xp, kind: kind))
            return
        }
        enqueue(Banner(title: title, subtitle: subtitle, accent: accent), seconds: 2.6, confetti: showConfetti, haptic: Haptics.success)
    }

    func nudge(title: String, subtitle: String) {
        enqueue(Banner(title: title, subtitle: subtitle, accent: Accent(hex: 0xFF9600)), seconds: 3.4, confetti: false, haptic: Haptics.warning)
    }

    /// Hold XP celebrations (e.g. the first sync after coming back) and show them as one banner.
    func beginCollecting() { if collecting == nil { collecting = [] } }

    func endCollecting(awayTitle: Bool) {
        guard let events = collecting else { return }
        collecting = nil
        // The flame first; the summary banner follows it.
        if let s = pendingStreak, !takeover {
            pendingStreak = nil
            withAnimation(.easeOut(duration: 0.35)) { streakLit = s }
        }
        guard !events.isEmpty else { return }
        if events.count == 1, let e = events.first {
            fire(title: e.title, subtitle: e.subtitle, accent: e.accent, confetti: e.confetti)
            return
        }
        let xp = events.reduce(0) { $0 + $1.xp }
        let checkpoints = events.filter { if case .checkpoint = $0.kind { true } else { false } }.count
        let goals = events.reduce(0) { if case .goals(let n) = $1.kind { $0 + n } else { $0 } }
        var parts: [String] = []
        if checkpoints > 0 { parts.append("\(checkpoints) checkpoint\(checkpoints == 1 ? "" : "s")") }
        if goals > 0 { parts.append("\(goals) goal\(goals == 1 ? "" : "s")") }
        let accents = Set(events.map(\.accent.hex))
        fire(title: awayTitle ? "+\(xp) XP while you were away" : "+\(xp) XP",
             subtitle: parts.isEmpty ? "Nice work" : parts.joined(separator: " · ") + " done",
             accent: accents.count == 1 ? events[0].accent : .neutral,
             confetti: checkpoints > 0)
    }

    private func enqueue(_ b: Banner, seconds: Double, confetti: Bool, haptic: @escaping () -> Void) {
        if banner == nil && !takeover {
            present(b, seconds: seconds, confetti: confetti, haptic: haptic)
        } else {
            queue.append((b, seconds, confetti, haptic))
        }
    }

    private func present(_ b: Banner, seconds: Double, confetti showConfetti: Bool, haptic: () -> Void) {
        haptic()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { banner = b }
        if showConfetti { confetti = (UUID(), b.accent) }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.banner = nil }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !self.takeover, !self.queue.isEmpty else { return }
            let next = self.queue.removeFirst()
            self.present(next.banner, seconds: next.seconds, confetti: next.confetti, haptic: next.haptic)
        }
    }
}

struct CelebrationOverlay: View {
    @Environment(CelebrationCenter.self) private var center

    var body: some View {
        ZStack(alignment: .top) {
            if let c = center.confetti {
                ConfettiView(accent: c.accent).id(c.id)
            }
            if let b = center.banner {
                // Blur that fades out downward, then a wash of the banner's color on top of it.
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                 .init(color: .black.opacity(0.85), location: 0.35),
                                                 .init(color: .black.opacity(0.35), location: 0.68),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 260)
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
                LinearGradient(stops: [.init(color: b.accent.base.opacity(0.55), location: 0),
                                       .init(color: b.accent.base.opacity(0.42), location: 0.3),
                                       .init(color: b.accent.base.opacity(0.2), location: 0.6),
                                       .init(color: b.accent.base.opacity(0.06), location: 0.82),
                                       .init(color: b.accent.base.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.title).display(22, 750)
                        Text(b.subtitle).font(.ui(14, .medium)).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(b.accent.on)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(b.accent.base))
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(b.accent.dark).offset(y: 5))
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

struct ConfettiView: View {
    let accent: Accent

    private struct Particle {
        let x: CGFloat, delay: Double, speed: CGFloat, wobble: Double, phase: Double
        let spin: Double, size: CGFloat, color: Color, round: Bool
    }

    @State private var start = Date()
    @State private var particles: [Particle] = []

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                for p in particles {
                    let lt = t - p.delay
                    guard lt > 0 else { continue }
                    let y = -20 + CGFloat(lt) * p.speed + CGFloat(lt * lt) * 140
                    let x = p.x * size.width + CGFloat(sin(lt * p.wobble + p.phase)) * 24
                    guard y < size.height + 20 else { continue }
                    var c = gc
                    c.opacity = max(0, 1 - lt / 3.2)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(lt * p.spin))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 3, width: p.size, height: p.round ? p.size : p.size * 0.6)
                    c.fill(p.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            let colors: [Color] = [accent.base, accent.base, accent.dark, accent.tint, Color(hex: 0xFFC800), Theme.ink]
            particles = (0..<80).map { _ in
                Particle(x: .random(in: 0...1), delay: .random(in: 0...0.45), speed: .random(in: 240...520),
                         wobble: .random(in: 2...5), phase: .random(in: 0...6), spin: .random(in: -7...7),
                         size: .random(in: 7...12), color: colors.randomElement()!, round: Bool.random())
            }
        }
    }
}

// MARK: - Bottom action bar

extension View {
    /// Pins a primary button (plus optional footnote) to the bottom while the content keeps scrolling
    /// behind it: the page background only starts halfway down the button, so content shows right
    /// up to its corners instead of being cut off above it.
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) { bar() }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .background {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 30)
                        Theme.background
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

/// Small helper text under a bottom button, aligned with the button's leading edge.
struct BarFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.ui(13)).foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Live accent glow

/// Slowly drifting mesh of accent shades, fading out downward. Used behind the project hero.
struct AccentGlow: View {
    let accent: Accent

    var body: some View {
        let ui = UIColor(accent.base)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors(t, h: h, s: s, b: b))
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black.opacity(0.85), location: 0.35),
                                     .init(color: .black.opacity(0.35), location: 0.7),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ speed: Double, _ phase: Double, _ amp: Double) -> Float { Float(sin(t * speed * 5 + phase) * amp) }
        return [
            [0, 0], [0.5 + w(0.31, 0, 0.24), 0], [1, 0],
            [0, 0.45 + w(0.27, 1, 0.16)], [0.5 + w(0.23, 2, 0.22), 0.5 + w(0.29, 3, 0.14)], [1, 0.5 + w(0.21, 4, 0.16)],
            [0, 1], [0.5 + w(0.19, 5, 0.24), 1], [1, 1],
        ]
    }

    private func colors(_ t: Double, h: CGFloat, s: CGFloat, b: CGFloat) -> [Color] {
        // Stays on the accent's own hue: shades breathe in brightness and saturation, the hue barely drifts.
        let gray = s < 0.2  // neutral photo accents carry a faint tint (≤ 0.18)
        func shade(_ i: Double, alpha: Double) -> Color {
            let hue = (Double(h) + sin(t * 1.2 + i * 1.7) * 0.018).truncatingRemainder(dividingBy: 1) + 1
            if gray {
                // Charcoal and grays need real contrast to read as a glow at all.
                let bri = min(0.75, max(0.18, Double(b) * (1.15 + 0.45 * sin(t * 1.4 + i * 2))))
                return Color(hue: hue.truncatingRemainder(dividingBy: 1), saturation: Double(s), brightness: bri).opacity(alpha * 0.85)
            }
            let sat = min(1, Double(s) * (1.0 + 0.12 * sin(t * 1.5 + i)))
            let bri = min(1, Double(b) * (1.0 + 0.1 * cos(t * 1.3 + i * 2)))
            return Color(hue: hue.truncatingRemainder(dividingBy: 1), saturation: sat, brightness: bri).opacity(alpha * 0.8)
        }
        return [
            shade(0, alpha: 0.9), shade(1, alpha: 0.8), shade(2, alpha: 0.9),
            shade(3, alpha: 0.6), shade(4, alpha: 0.45), shade(5, alpha: 0.6),
            shade(6, alpha: 0.15), shade(7, alpha: 0.08), shade(8, alpha: 0.15),
        ]
    }
}

/// Centered over everything, played like a short scene: the screen blurs, then someone impressed types three
/// lines at you ("Hold up." → "Already finished?" → "You're killing it!"), then the number of days early lands
/// as a solid 3D block in the project's color and sways gently. Tap skips the intro, then closes.
struct ShipOverlay: View {
    @Environment(CelebrationCenter.self) private var center
    /// Which reaction is on screen; nil before the first and once the number shows.
    @State private var line: Int?
    /// Letters of the current line typed so far.
    @State private var typed = 0
    @State private var caretOn = true
    @State private var reveal = false
    @State private var landed = false
    @State private var caption = false

    var body: some View {
        if let m = center.ship {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                RadialGradient(colors: [m.accent.base.opacity(reveal ? 0.35 : 0.18), m.accent.base.opacity(0.06)], center: .center,
                               startRadius: 20, endRadius: 420)
                    .ignoresSafeArea()
                if let line, !reveal {
                    reaction(m.reactions[line])
                        .id(line)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(y: -10))))
                }
                if reveal { number(m) }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if reveal { center.endShip() } else { showNumber() }
            }
            .transition(.opacity)
            .task(id: m.id) { await play(m) }
        }
    }

    /// A line being typed out, like someone writing to you. The full line sits invisibly underneath so the
    /// text grows in place instead of re-centering with every letter.
    private func reaction(_ text: String) -> some View {
        let shown = String(text.prefix(typed))
        return Text(text).display(44, 800).foregroundStyle(.clear)
            .overlay(alignment: .leading) {
                (Text(shown).foregroundStyle(Theme.ink) + Text("|").foregroundStyle(Theme.ink.opacity(caretOn ? 0.8 : 0)))
                    .display(44, 800)
                    .fixedSize()
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 24)
    }

    private func number(_ m: CelebrationCenter.ShipMoment) -> some View {
        VStack(spacing: 6) {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ExtrudedText(text: "\(m.daysEarly)", size: 190, accent: m.accent)
                    .rotation3DEffect(.degrees(landed ? 9 * sin(t * 1.3) : -35), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .rotation3DEffect(.degrees(landed ? 4 * sin(t * 0.9 + 1) : 70), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.5)
            }
            .scaleEffect(landed ? 1 : 0.55)
            .opacity(landed ? 1 : 0)
            .background(alignment: .bottom) {
                Ellipse().fill(Color.black.opacity(0.14)).frame(width: 220, height: 30).blur(radius: 16).offset(y: 8)
                    .opacity(landed ? 1 : 0)
            }
            ExtrudedText(text: m.daysEarly == 1 ? "day early" : "days early", size: 40, accent: m.accent, weight: 800)
                .opacity(caption ? 1 : 0)
                .offset(y: caption ? 0 : 14)
            Text("\(m.project) shipped · +\(m.xp) XP")
                .font(.ui(16, .semibold)).foregroundStyle(Theme.secondary)
                .padding(.top, 10)
                .opacity(caption ? 1 : 0)
        }
        .padding(.horizontal, 24)
    }

    private func play(_ m: CelebrationCenter.ShipMoment) async {
        line = nil; typed = 0; reveal = false; landed = false; caption = false
        // A beat of blur before anyone speaks.
        try? await Task.sleep(for: .milliseconds(350))
        for (i, text) in m.reactions.enumerated() {
            guard !Task.isCancelled, !reveal else { return }
            typed = 0
            caretOn = true
            withAnimation(.easeOut(duration: 0.15)) { line = i }
            try? await Task.sleep(for: .milliseconds(120))
            // Typed like a person: steady letters, a little hitch after punctuation.
            for (n, ch) in text.enumerated() {
                guard !Task.isCancelled, !reveal else { return }
                typed = n + 1
                if ch != " " { Haptics.select() }
                let pause = ".?!,".contains(ch) ? 140 : ch == " " ? 70 : 45
                try? await Task.sleep(for: .milliseconds(pause))
            }
            // Let it sit for a moment with the cursor blinking.
            for _ in 0..<(i == m.reactions.count - 1 ? 4 : 3) {
                guard !Task.isCancelled, !reveal else { return }
                try? await Task.sleep(for: .milliseconds(170))
                caretOn.toggle()
            }
            caretOn = false
            if i < m.reactions.count - 1 {
                withAnimation(.easeIn(duration: 0.15)) { line = nil }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
        guard !Task.isCancelled, !reveal else { return }
        await landNumber(m)
    }

    private func showNumber() {
        guard let m = center.ship else { return }
        Task { await landNumber(m) }
    }

    private func landNumber(_ m: CelebrationCenter.ShipMoment) async {
        guard !reveal else { return }
        withAnimation(.easeOut(duration: 0.2)) { line = nil; reveal = true }
        center.confetti = (UUID(), m.accent)
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { landed = true }
        try? await Task.sleep(for: .milliseconds(180))
        Haptics.heavy()
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { caption = true }
        try? await Task.sleep(for: .seconds(3.4))
        if center.ship?.id == m.id { center.endShip() }
    }
}

