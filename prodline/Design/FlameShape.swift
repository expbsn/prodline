import SwiftUI

/// Prodline's own cartoon flame: a round belly, a tall tip leaning a little right, and a tongue on each side.
/// `time` makes it burn — the tip wavers, the tongues lick up and sway, the sides breathe — so it moves like
/// fire instead of an icon being scaled. `life` scales that motion (0 = a still flame, for badges).
struct FlameShape: Shape {
    var time: Double = 0
    var life: Double = 1
    /// How far it has caught: around 0.2 it's a low ember at the base, at 1 the full flame. Growing is the
    /// outline itself rising — the tip first, the side tongues a little later — not the flame being scaled.
    var grow: Double = 1

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(time, AnimatablePair(life, grow)) }
        set { time = newValue.first; life = newValue.second.first; grow = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        // Designed in a 100 × 130 box, scaled to fit the rect.
        let sx = rect.width / 100, sy = rect.height / 130
        let t = time
        let a = life
        let g = max(0.05, grow)
        // A few unrelated sines per point read as organic flicker rather than a loop.
        func w(_ f1: Double, _ f2: Double, _ phase: Double) -> Double { (sin(t * f1 + phase) * 0.65 + sin(t * f2 + phase * 1.7) * 0.35) * a }
        /// Height above the base, grown: the body rises ahead of its width (so a small flame is a teardrop,
        /// not a squat cone), the tip leads further, the tongues follow last.
        func rise(_ y: Double, lead: Double = 0.6) -> Double {
            let k = pow(min(g, 1), lead) * (g > 1 ? g : 1)
            return 130 - (130 - y) * k
        }
        /// Narrower while small, full width once it burns.
        func spread(_ x: Double) -> Double { 50 + (x - 50) * (0.25 + 0.75 * min(g, 1)) }
        func p(_ x: Double, _ y: Double, lead: Double = 0.6) -> CGPoint {
            CGPoint(x: rect.minX + spread(x) * sx, y: rect.minY + rise(y, lead: lead) * sy)
        }

        let tip = (x: 58 + 6 * w(4.1, 7.3, 0), y: 2 + 5 * abs(w(5.2, 9.1, 1)))
        let left = (x: 16 + 4 * w(5.6, 8.7, 2), y: 38 + 7 * w(6.3, 10.1, 3))
        let right = (x: 88 + 4 * w(6.1, 9.4, 4), y: 30 + 7 * w(5.8, 11.2, 5))
        let notchL = (x: 32 + 2 * w(4.4, 7.7, 6), y: 58 + 3 * w(5.1, 8.2, 7))
        let notchR = (x: 74 + 2 * w(4.8, 8.4, 8), y: 46 + 3 * w(5.5, 9.3, 9))
        let breath = 1.5 * w(3.2, 5.1, 10)

        // While small it's a clean teardrop; the tongues and notches come out of its outline as it grows.
        // Hidden, every point sits on the teardrop's sides, so there are no odd shoulders.
        let out = min(1, max(0, (g - 0.4) / 0.5))
        func bez(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double), _ d: (Double, Double), _ u: Double) -> (x: Double, y: Double) {
            let v = 1 - u
            return (v * v * v * a.0 + 3 * v * v * u * b.0 + 3 * v * u * u * c.0 + u * u * u * d.0,
                    v * v * v * a.1 + 3 * v * v * u * b.1 + 3 * v * u * u * c.1 + u * u * u * d.1)
        }
        // The teardrop's two sides, from the widest point of the belly up to the tip.
        func leftEdge(_ u: Double) -> (x: Double, y: Double) { bez((6, 90), (6, 52), (36, 20), (tip.x, tip.y), u) }
        func rightEdge(_ u: Double) -> (x: Double, y: Double) { bez((tip.x, tip.y), (78, 20), (96, 52), (96, 88), u) }
        func mix(_ hidden: (x: Double, y: Double), _ shown: (x: Double, y: Double)) -> (x: Double, y: Double) {
            (hidden.x + (shown.x - hidden.x) * out, hidden.y + (shown.y - hidden.y) * out)
        }
        let lt = mix(leftEdge(0.3), left)
        let nl = mix(leftEdge(0.55), notchL)
        let nr = mix(rightEdge(0.35), notchR)
        let rt = mix(rightEdge(0.6), right)
        // Control points: along the teardrop while hidden, the tongue shapes once out.
        let c1 = mix(leftEdge(0.12), (8 - breath, 70))
        let c2 = mix(leftEdge(0.22), (lt.x - 6, lt.y + 18))
        let c3 = mix(leftEdge(0.4), (lt.x + 6, lt.y + 10))
        let c4 = mix(leftEdge(0.48), (nl.x - 6, nl.y - 4))
        let c5 = mix(leftEdge(0.72), (nl.x + 2, 34))
        let c6 = mix(leftEdge(0.88), (tip.x - 14, tip.y + 20))
        let c7 = mix(rightEdge(0.12), (tip.x + 10, tip.y + 18))
        let c8 = mix(rightEdge(0.26), (nr.x - 2, nr.y - 14))
        let c9 = mix(rightEdge(0.45), (nr.x + 4, nr.y - 6))
        let c10 = mix(rightEdge(0.52), (rt.x - 6, rt.y + 8))
        let c11 = mix(rightEdge(0.75), (rt.x + 6, rt.y + 16))
        let c12 = mix(rightEdge(0.9), (98 + breath, 66))
        // Hidden, everything rises together (a scaled teardrop); out, the tip leads and the tongues lag.
        let tipLead = 0.6 - 0.05 * out
        let tongueLead = 0.6 + 0.4 * out

        var path = Path()
        path.move(to: p(50, 130))
        // Belly, left side, up to the left tongue.
        path.addCurve(to: p(6 - breath, 90), control1: p(16, 130), control2: p(4 - breath, 112))
        path.addCurve(to: p(lt.x, lt.y, lead: tongueLead), control1: p(c1.x, c1.y), control2: p(c2.x, c2.y, lead: tongueLead))
        // Down into the notch, then up the long main tongue to the tip.
        path.addCurve(to: p(nl.x, nl.y), control1: p(c3.x, c3.y, lead: tongueLead), control2: p(c4.x, c4.y))
        path.addCurve(to: p(tip.x, tip.y, lead: tipLead), control1: p(c5.x, c5.y, lead: tipLead), control2: p(c6.x, c6.y, lead: tipLead))
        // Down the right of the tip into the right notch, up to the right tongue.
        path.addCurve(to: p(nr.x, nr.y), control1: p(c7.x, c7.y, lead: tipLead), control2: p(c8.x, c8.y))
        path.addCurve(to: p(rt.x, rt.y, lead: tongueLead), control1: p(c9.x, c9.y), control2: p(c10.x, c10.y, lead: tongueLead))
        // Right side down and round the belly.
        path.addCurve(to: p(96 + breath, 88), control1: p(c11.x, c11.y, lead: tongueLead), control2: p(c12.x, c12.y))
        path.addCurve(to: p(50, 130), control1: p(94 + breath, 116), control2: p(78, 130))
        path.closeSubpath()
        return path
    }
}

/// The small still flame for badges: the outer flame with a yellow heart.
struct FlameMark: View {
    var color: Color
    var lit: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            FlameShape(life: 0).fill(color)
            FlameShape(life: 0)
                .fill(lit ? Color(hex: 0xFFC800) : .white.opacity(0.55))
                .scaleEffect(0.5, anchor: .bottom)
                .offset(y: -1)
        }
        .aspectRatio(100 / 130, contentMode: .fit)
    }
}

/// The streak flame as a solid cartoon object that is always burning: nested layers (red-orange, orange,
/// yellow, a white-hot core) on a dark extruded body, tongues licking and swaying, each layer at its own
/// rhythm. `grow` takes it from a tiny teardrop to the full flame; `bright` from dim and smoky to lit with glow.
struct BurningFlame: View {
    var grow: Double
    var bright: Double
    var width: CGFloat = 150
    /// When it started burning; the flicker eases in over a moment from then.
    var alive: Date = .distantPast

    private var h: CGFloat { width * 1.3 }

    private struct Layer { let scale: CGFloat; let phase: Double; let speed: Double; let colors: [Int] }
    private static let layers = [
        Layer(scale: 1.0, phase: 0, speed: 1.0, colors: [0xFF8A00, 0xFF4B1F]),
        Layer(scale: 0.74, phase: 1.3, speed: 1.15, colors: [0xFFB000, 0xFF8A00]),
        Layer(scale: 0.5, phase: 2.6, speed: 1.3, colors: [0xFFE04A, 0xFFB000]),
        Layer(scale: 0.27, phase: 3.9, speed: 1.5, colors: [0xFFFFFF, 0xFFF0A0]),
    ]

    var body: some View {
        let s = width / 150
        TimelineView(.animation) { tl in
            let since = max(0, tl.date.timeIntervalSince(alive))
            let life = min(1, 0.4 + since / 0.8)
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                ForEach((1...8).reversed(), id: \.self) { i in
                    FlameShape(time: t, life: life, grow: grow).fill(Color(hex: 0x8A2410))
                        .offset(x: CGFloat(i) * 0.6 * s * min(1, grow + 0.2), y: CGFloat(i) * 1.1 * s * min(1, grow + 0.2))
                }
                ForEach(Self.layers.indices, id: \.self) { i in
                    let l = Self.layers[i]
                    FlameShape(time: t * l.speed + l.phase, life: life * (1 + Double(i) * 0.25), grow: grow)
                        .fill(LinearGradient(colors: l.colors.map { Color(hex: $0) }, startPoint: .bottom, endPoint: .top))
                        .frame(width: width * l.scale, height: h * l.scale)
                        .offset(y: -CGFloat(i) * 6 * s * min(1, grow))
                }
                // Gloss on the left of the belly, like the chunky buttons; it grows with the flame.
                Capsule().fill(.white.opacity(0.3 * bright))
                    .frame(width: 9 * s * (0.4 + 0.6 * min(1, grow)), height: 46 * s * min(1, grow + 0.1))
                    .rotationEffect(.degrees(16))
                    .offset(x: -width * 0.3 * (0.25 + 0.75 * min(1, grow)), y: -h * 0.2 * min(1, grow))
                    .blur(radius: 0.5)
            }
            .frame(width: width, height: h)
            // Dim and smoky while it's small; full color once it catches.
            .saturation(0.55 + 0.45 * bright)
            .brightness(-0.28 * (1 - bright))
        }
        // No glow until it actually catches.
        .shadow(color: Color(hex: 0xFF9600).opacity(0.9 * bright), radius: 16 * s)
        .shadow(color: Color(hex: 0xFF9600).opacity(0.6 * bright), radius: 42 * s)
        .shadow(color: Color(hex: 0xFF4B00).opacity(0.4 * bright), radius: 90 * s)
    }
}

