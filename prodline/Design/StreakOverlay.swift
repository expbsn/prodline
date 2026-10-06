import SwiftUI

/// Today's first progress: the screen darkens, then the streak flame lights up in the middle — a solid 3D
/// flame with a glowing halo and sparks — and the streak ticks up by one. Banners (like the XP that came
/// with it) wait until it's over. Tap to skip.
struct StreakOverlay: View {
    @Environment(CelebrationCenter.self) private var center
    @State private var dim = false
    @State private var lit = false
    @State private var shown = 0
    @State private var label = false

    private static let orange = Color(hex: 0xFF9600)

    var body: some View {
        if let m = center.streakLit {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(dim ? 1 : 0)
                Color.black.opacity(dim ? 0.6 : 0)
                // Warm light thrown by the flame onto the darkened screen.
                RadialGradient(colors: [Self.orange.opacity(0.45), Self.orange.opacity(0.12), .clear], center: .center,
                               startRadius: 10, endRadius: 330)
                    .offset(y: -40)
                    .opacity(lit ? 1 : 0)
                VStack(spacing: 40) {
                    // The sparks float over the flame without taking part in the layout.
                    Flame3D(lit: lit)
                        .frame(height: 190, alignment: .bottom)
                        .overlay(alignment: .bottom) {
                            Sparks(active: lit).frame(width: 260, height: 320).offset(y: -20)
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
        dim = false; lit = false; label = false
        shown = max(0, m.days - 1)
        // The room goes dark first.
        withAnimation(.easeOut(duration: 0.4)) { dim = true }
        try? await Task.sleep(for: .milliseconds(450))
        // Ignition.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { lit = true }
        Haptics.heavy()
        try? await Task.sleep(for: .milliseconds(120))
        Haptics.success()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { label = true }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = m.days }
        Haptics.soft()
        try? await Task.sleep(for: .seconds(2.2))
        if center.streakLit?.id == m.id { center.endStreak() }
    }
}

/// The flame as a solid object: a dark orange body behind the face for depth, the lit face filling from
/// the bottom up, a bright core, layered glow, and a slow flicker and sway once it burns.
private struct Flame3D: View {
    let lit: Bool
    private let size: CGFloat = 150

    var body: some View {
        TimelineView(.animation(paused: !lit)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let flicker = lit ? 1 + 0.035 * sin(t * 9) + 0.02 * sin(t * 14.3) : 1
            ZStack {
                ForEach((1...9).reversed(), id: \.self) { i in
                    flame(size).foregroundStyle(lit ? Color(hex: 0xC2410C) : Color(hex: 0x3A3A3C))
                        .offset(x: CGFloat(i) * 0.6, y: CGFloat(i) * 1.1)
                }
                flame(size).foregroundStyle(Color(hex: 0x636366))
                // The hot core, under the face: it glows through the flame's inner cutout.
                Ellipse()
                    .fill(RadialGradient(colors: [.white, Color(hex: 0xFFE680), Color(hex: 0xFFB020).opacity(0)],
                                         center: .center, startRadius: 2, endRadius: size * 0.28))
                    .frame(width: size * 0.5, height: size * 0.62)
                    .offset(y: size * 0.18)
                    .opacity(lit ? 1 : 0)
                flame(size)
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD23F), Color(hex: 0xFF9600), Color(hex: 0xFF5A1F)],
                                                    startPoint: .bottom, endPoint: .top))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: lit ? size * 1.3 : 0)
                    }
            }
            .scaleEffect(x: 1, y: flicker, anchor: .bottom)
            .scaleEffect(lit ? 1 : 0.82, anchor: .bottom)
            .shadow(color: Color(hex: 0xFF9600).opacity(lit ? 0.95 : 0), radius: 16)
            .shadow(color: Color(hex: 0xFF9600).opacity(lit ? 0.65 : 0), radius: 42)
            .shadow(color: Color(hex: 0xFF4B00).opacity(lit ? 0.45 : 0), radius: 90)
            .rotation3DEffect(.degrees(lit ? 7 * sin(t * 1.1) : -18), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(lit ? 3 * sin(t * 0.8 + 1) : 10), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
        }
    }

    private func flame(_ s: CGFloat) -> some View {
        Image(systemName: "flame.fill").font(.system(size: s, weight: .regular))
    }
}

/// Embers rising from the flame and fading out, on a loop while it burns.
private struct Sparks: View {
    let active: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: !active)) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard active else { return }
                let base = CGPoint(x: size.width / 2, y: size.height * 0.82)
                for i in 0..<34 {
                    // Fixed per-spark randomness, so each one keeps its own path.
                    let r1 = fract(sin(Double(i) * 12.9898) * 43758.5453)
                    let r2 = fract(sin(Double(i) * 78.233) * 12345.678)
                    let period = 1.1 + r2 * 0.7
                    let age = (t + r1 * period).truncatingRemainder(dividingBy: period) / period
                    let x = base.x + CGFloat((r1 - 0.5) * 90) + CGFloat(sin(age * 6 + r2 * 6) * 14 * age)
                    let y = base.y - CGFloat(age * (150 + r2 * 120))
                    let s = CGFloat(2 + r2 * 3) * CGFloat(1 - age * 0.6)
                    let color = r1 > 0.5 ? Color(hex: 0xFFD23F) : Color(hex: 0xFF9600)
                    ctx.opacity = (1 - age) * min(1, age * 6)
                    ctx.addFilter(.blur(radius: 0.6))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s, width: s, height: s * 2)), with: .color(color))
                }
            }
        }
        .onChange(of: active) { if active { start = Date() } }
        .allowsHitTesting(false)
    }

    private func fract(_ x: Double) -> Double { x - x.rounded(.down) }
}
