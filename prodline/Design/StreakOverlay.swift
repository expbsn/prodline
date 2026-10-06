import SwiftUI

/// Today's first progress: the room slowly goes dark around the edges, the unlit flame emerges, then it
/// catches — filling from the bottom up with a burst of sparks — and keeps burning, tongues licking and
/// flickering. The streak ticks up by one. Banners (like the XP that came with it) wait until it's over. Tap to skip.
struct StreakOverlay: View {
    @Environment(CelebrationCenter.self) private var center
    @State private var dim = false
    @State private var ember = false
    @State private var lit = false
    @State private var shown = 0
    @State private var label = false

    private static let orange = Color(hex: 0xFF9600)

    var body: some View {
        if let m = center.streakLit {
            ZStack {
                // The screen stays visible: lightly blurred and dimmed, darker toward the edges.
                Rectangle().fill(.ultraThinMaterial).opacity(dim ? 0.35 : 0)
                Color.black.opacity(dim ? 0.38 : 0)
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 120, endRadius: 560)
                    .opacity(dim ? 1 : 0)
                // Warm light thrown by the flame once it burns.
                RadialGradient(colors: [Self.orange.opacity(0.4), Self.orange.opacity(0.1), .clear], center: .center,
                               startRadius: 10, endRadius: 320)
                    .offset(y: -60)
                    .opacity(lit ? 1 : 0)
                VStack(spacing: 40) {
                    Flame3D(lit: lit, ember: ember)
                        .frame(height: 190, alignment: .bottom)
                        .overlay(alignment: .bottom) {
                            Sparks(burst: lit).frame(width: 340, height: 380).offset(y: 40)
                        }
                    VStack(spacing: 2) {
                        Text("\(shown)").display(72, 850).foregroundStyle(.white).monospacedDigit()
                            .contentTransition(.numericText(value: Double(shown)))
                        Text("day streak").font(.ui(18, .bold)).foregroundStyle(.white.opacity(0.8))
                            .textCase(.uppercase).tracking(2)
                    }
                    .opacity(label ? 1 : 0)
                    .offset(y: label ? 0 : 10)
                }
                .offset(y: -20)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { center.endStreak() }
            .transition(.opacity)
            .task(id: m.id) { await play(m) }
        }
    }

    private func play(_ m: CelebrationCenter.StreakMoment) async {
        dim = false; ember = false; lit = false; label = false
        shown = max(0, m.days - 1)
        // Slowly, the room goes dark.
        withAnimation(.easeIn(duration: 1.3)) { dim = true }
        try? await Task.sleep(for: .milliseconds(700))
        // Something is there: the unlit flame emerges.
        withAnimation(.easeInOut(duration: 0.6)) { ember = true }
        Haptics.soft()
        try? await Task.sleep(for: .milliseconds(1100))
        // Then it catches.
        lit = true
        Haptics.heavy()
        try? await Task.sleep(for: .milliseconds(140))
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { label = true }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = m.days }
        Haptics.soft()
        try? await Task.sleep(for: .seconds(2.0))
        if center.streakLit?.id == m.id { center.endStreak() }
    }
}

/// The flame as a solid cartoon object that is always burning: nested layers (red-orange, orange, yellow, a
/// white-hot core) on a dark extruded body. It appears as a tiny flickering teardrop and keeps growing in the
/// dark, dim and without glow; when it catches it shoots up past full height and settles into the full flame,
/// tongues licking and swaying, each layer at its own rhythm.
private struct Flame3D: View {
    let lit: Bool
    let ember: Bool
    @State private var grow: Double = 0.05
    @State private var bright: Double = 0
    @State private var appeared = Date.distantFuture

    private let w: CGFloat = 150
    private var h: CGFloat { w * 1.3 }

    private struct Layer { let scale: CGFloat; let phase: Double; let speed: Double; let colors: [Int] }
    private let layers = [
        Layer(scale: 1.0, phase: 0, speed: 1.0, colors: [0xFF8A00, 0xFF4B1F]),
        Layer(scale: 0.74, phase: 1.3, speed: 1.15, colors: [0xFFB000, 0xFF8A00]),
        Layer(scale: 0.5, phase: 2.6, speed: 1.3, colors: [0xFFE04A, 0xFFB000]),
        Layer(scale: 0.27, phase: 3.9, speed: 1.5, colors: [0xFFFFFF, 0xFFF0A0]),
    ]

    var body: some View {
        TimelineView(.animation) { tl in
            // It flickers from the first frame; the motion just eases in over a moment.
            let since = max(0, tl.date.timeIntervalSince(appeared))
            let life = min(1, 0.4 + since / 0.8)
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                ForEach((1...8).reversed(), id: \.self) { i in
                    FlameShape(time: t, life: life, grow: grow).fill(Color(hex: 0x8A2410))
                        .offset(x: CGFloat(i) * 0.6 * min(1, grow + 0.2), y: CGFloat(i) * 1.1 * min(1, grow + 0.2))
                }
                ForEach(layers.indices, id: \.self) { i in
                    let l = layers[i]
                    FlameShape(time: t * l.speed + l.phase, life: life * (1 + Double(i) * 0.25), grow: grow)
                        .fill(LinearGradient(colors: l.colors.map { Color(hex: $0) }, startPoint: .bottom, endPoint: .top))
                        .frame(width: w * l.scale, height: h * l.scale)
                        .offset(y: -CGFloat(i) * 6 * min(1, grow))
                }
                // Gloss on the left of the belly, like the chunky buttons; it grows with the flame.
                Capsule().fill(.white.opacity(0.3 * bright))
                    .frame(width: 9 * (0.4 + 0.6 * min(1, grow)), height: 46 * min(1, grow + 0.1))
                    .rotationEffect(.degrees(16))
                    .offset(x: -w * 0.3 * (0.25 + 0.75 * min(1, grow)), y: -h * 0.2 * min(1, grow))
                    .blur(radius: 0.5)
            }
            .frame(width: w, height: h)
            // Dim and smoky while it's small in the dark; full color once it catches.
            .saturation(0.55 + 0.45 * bright)
            .brightness(-0.28 * (1 - bright))
        }
        // No glow until it actually catches.
        .shadow(color: Color(hex: 0xFF9600).opacity(0.9 * bright), radius: 16)
        .shadow(color: Color(hex: 0xFF9600).opacity(0.6 * bright), radius: 42)
        .shadow(color: Color(hex: 0xFF4B00).opacity(0.4 * bright), radius: 90)
        .opacity(lit || ember ? 1 : 0)
        .onChange(of: ember) {
            guard ember else { return }
            // A tiny flame appears and slowly grows in the dark.
            appeared = .now
            grow = 0.05
            withAnimation(.easeOut(duration: 1.6)) { grow = 0.34 }
        }
        .onChange(of: lit) {
            guard lit else { grow = 0.05; bright = 0; return }
            // It catches: shoots up past full height, then settles.
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { grow = 1 }
            withAnimation(.easeOut(duration: 0.35)) { bright = 1 }
        }
    }
}

/// A burst of sparks the moment the flame catches: thrown up and out, slowing and falling back as they fade.
private struct Sparks: View {
    let burst: Bool
    @State private var start = Date.distantFuture
    private let count = 90
    private let life = 1.5

    var body: some View {
        TimelineView(.animation(paused: !burst)) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard burst, t >= 0 else { return }
                let base = CGPoint(x: size.width / 2, y: size.height * 0.62)
                for i in 0..<count {
                    // Fixed per-spark randomness, so each keeps its own path.
                    let r1 = fract(sin(Double(i) * 12.9898) * 43758.5453)
                    let r2 = fract(sin(Double(i) * 78.233) * 12345.678)
                    let r3 = fract(sin(Double(i) * 39.425) * 24634.6345)
                    let delay = r3 * 0.35          // most leave right away, a few trail
                    let age = (t - delay) / life
                    guard age > 0, age < 1 else { continue }
                    // Mostly upward, fanned out; gravity pulls them back.
                    let angle = -Double.pi / 2 + (r1 - 0.5) * 2.3
                    let speed = 220 + r2 * 330
                    let s = age * life
                    let x = base.x + CGFloat(cos(angle) * speed * s)
                    let y = base.y + CGFloat(sin(angle) * speed * s + 260 * s * s)
                    let size = CGFloat(2 + r2 * 4) * CGFloat(1 - age * 0.7)
                    let color = r3 > 0.55 ? Color(hex: 0xFFD23F) : r3 > 0.2 ? Color(hex: 0xFF9600) : .white
                    ctx.opacity = (1 - age) * min(1, age * 10)
                    // Streaks point the way they fly.
                    let heading = atan2(sin(angle) * speed + 520 * s, cos(angle) * speed)
                    let p = Path(ellipseIn: CGRect(x: -size, y: -size / 2, width: size * 2.6, height: size))
                        .applying(CGAffineTransform(rotationAngle: heading))
                        .applying(CGAffineTransform(translationX: x, y: y))
                    ctx.fill(p, with: .color(color))
                }
                // Then a few embers keep drifting up from the tip while it burns.
                guard t > 0.5 else { return }
                for i in 0..<12 {
                    let r1 = fract(sin(Double(i) * 91.17) * 4373.1)
                    let r2 = fract(sin(Double(i) * 23.71) * 9183.4)
                    let period = 1.3 + r2 * 0.8
                    let age = ((t - 0.5) + r1 * period).truncatingRemainder(dividingBy: period) / period
                    let x = base.x + CGFloat((r1 - 0.5) * 50 + sin(age * 5 + r2 * 6) * 10)
                    let y = base.y - 130 - CGFloat(age * (110 + r2 * 90))
                    let size = CGFloat(1.5 + r2 * 2.5) * CGFloat(1 - age * 0.5)
                    ctx.opacity = (1 - age) * min(1, age * 5) * 0.9
                    ctx.fill(Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
                             with: .color(r1 > 0.5 ? Color(hex: 0xFFD23F) : Color(hex: 0xFF9600)))
                }
            }
        }
        .onChange(of: burst) { if burst { start = Date() } }
        .allowsHitTesting(false)
    }

    private func fract(_ x: Double) -> Double { x - x.rounded(.down) }
}
