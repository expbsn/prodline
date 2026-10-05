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

@Observable
final class CelebrationCenter {
    struct Banner: Equatable { var title: String; var subtitle: String; var accent: Accent }
    var banner: Banner?
    var confetti: (id: UUID, accent: Accent)?
    private var dismissTask: Task<Void, Never>?

    func fire(title: String, subtitle: String, accent: Accent = .neutral, confetti showConfetti: Bool = true) {
        Haptics.success()
        show(Banner(title: title, subtitle: subtitle, accent: accent), seconds: 2.6)
        if showConfetti { confetti = (UUID(), accent) }
    }

    func nudge(title: String, subtitle: String) {
        Haptics.warning()
        show(Banner(title: title, subtitle: subtitle, accent: Accent(hex: 0xFF9600)), seconds: 3.4)
    }

    private func show(_ b: Banner, seconds: Double) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { banner = b }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.banner = nil }
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
        // Neighbouring hues swing in and out; saturation is pushed well past the accent itself.
        let gray = s < 0.2  // neutral photo accents carry a faint tint (≤ 0.18)
        func shade(_ i: Double, alpha: Double) -> Color {
            let dh = sin(t * 1.2 + i * 1.7) * 0.08
            let sat = gray ? s : min(1, max(s * 1.3, 0.8) + 0.12 * sin(t * 1.5 + i))
            let bri = gray ? b * (0.85 + 0.15 * sin(t * 1.4 + i * 2)) : min(1, max(b, 0.85) + 0.08 * cos(t * 1.3 + i * 2))
            var hue = Double(h) + dh
            hue -= floor(hue)
            // Gray accents (black and white covers) get a soft smoke instead of a dark slab.
            return Color(hue: hue, saturation: Double(sat), brightness: Double(bri)).opacity(gray ? alpha * 0.4 : alpha)
        }
        return [
            shade(0, alpha: 0.9), shade(1, alpha: 0.8), shade(2, alpha: 0.9),
            shade(3, alpha: 0.6), shade(4, alpha: 0.45), shade(5, alpha: 0.6),
            shade(6, alpha: 0.15), shade(7, alpha: 0.08), shade(8, alpha: 0.15),
        ]
    }
}
