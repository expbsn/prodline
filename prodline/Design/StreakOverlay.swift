import SwiftUI

/// Today's first progress: the room slowly goes dark around the edges, a faint ember flickers in the middle,
/// then the streak flame catches — a cartoon squash and stretch with a burst of sparks — and settles. The
/// streak ticks up by one. Banners (like the XP that came with it) wait until it's over. Tap to skip.
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
        // Something's there: a faint ember in the middle.
        withAnimation(.easeInOut(duration: 0.6)) { ember = true }
        Haptics.soft()
        try? await Task.sleep(for: .milliseconds(850))
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

/// Squash and stretch for the ignition.
private struct Stretch {
    var x: CGFloat = 0.9
    var y: CGFloat = 0.9
}

/// The flame as a solid cartoon object: a dark orange body behind the face for depth, a bright core glowing
/// through its cutout, layered glow. Ignition squashes, shoots up tall and thin, and settles — then holds still.
private struct Flame3D: View {
    let lit: Bool
    let ember: Bool
    private let size: CGFloat = 150

    var body: some View {
        ZStack {
            ForEach((1...9).reversed(), id: \.self) { i in
                flame(size).foregroundStyle(lit ? Color(hex: 0xC2410C) : Color(hex: 0x2C2C2E))
                    .offset(x: CGFloat(i) * 0.6, y: CGFloat(i) * 1.1)
            }
            flame(size).foregroundStyle(Color(hex: 0x48484A))
            // The hot core, under the face: it glows through the flame's inner cutout. Before ignition, a faint ember.
            core
            flame(size)
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD23F), Color(hex: 0xFF9600), Color(hex: 0xFF5A1F)],
                                                startPoint: .bottom, endPoint: .top))
                .opacity(lit ? 1 : 0)
        }
        // The unlit flame only emerges out of the dark together with the ember.
        .opacity(lit || ember ? 1 : 0)
        .shadow(color: Color(hex: 0xFF9600).opacity(lit ? 0.95 : ember ? 0.35 : 0), radius: 16)
        .shadow(color: Color(hex: 0xFF9600).opacity(lit ? 0.65 : 0), radius: 42)
        .shadow(color: Color(hex: 0xFF4B00).opacity(lit ? 0.45 : 0), radius: 90)
        .keyframeAnimator(initialValue: Stretch(), trigger: lit) { view, s in
            view.scaleEffect(x: lit ? s.x : 0.9, y: lit ? s.y : 0.9, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(1.42, duration: 0.14)   // squash
                CubicKeyframe(0.68, duration: 0.2)    // stretch up
                CubicKeyframe(1.14, duration: 0.16)
                CubicKeyframe(0.96, duration: 0.14)
                CubicKeyframe(1.0, duration: 0.14)    // and still
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(0.5, duration: 0.14)
                CubicKeyframe(1.42, duration: 0.2)
                CubicKeyframe(0.88, duration: 0.16)
                CubicKeyframe(1.04, duration: 0.14)
                CubicKeyframe(1.0, duration: 0.14)
            }
        }
    }

    private var core: some View {
        Ellipse()
            .fill(RadialGradient(colors: [.white, Color(hex: 0xFFE680), Color(hex: 0xFFB020).opacity(0)],
                                 center: .center, startRadius: 2, endRadius: size * 0.28))
            .frame(width: size * 0.5, height: size * 0.62)
            .offset(y: size * 0.18)
            .phaseAnimator([0.3, 0.6], trigger: ember) { view, flicker in
                view.opacity(lit ? 1 : ember ? flicker : 0)
            } animation: { _ in .easeInOut(duration: 0.3) }
    }

    private func flame(_ s: CGFloat) -> some View {
        Image(systemName: "flame.fill").font(.system(size: s, weight: .regular))
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
                guard burst, t >= 0, t < life + 0.6 else { return }
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
            }
        }
        .onChange(of: burst) { if burst { start = Date() } }
        .allowsHitTesting(false)
    }

    private func fract(_ x: Double) -> Double { x - x.rounded(.down) }
}
