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

        // The tongues only come out once it's well alight: while small they sit down in the belly's outline.
        let out = min(1, max(0, (g - 0.45) / 0.5))
        let lt = (x: 20 + (left.x - 20) * out, y: 70 + (left.y - 70) * out)
        let rt = (x: 84 + (right.x - 84) * out, y: 64 + (right.y - 64) * out)
        let nl = (x: 34 + (notchL.x - 34) * out, y: 60 + (notchL.y - 60) * out)
        let nr = (x: 70 + (notchR.x - 70) * out, y: 56 + (notchR.y - 56) * out)

        // Hidden tongues move with the body; once out, they lag behind it.
        let tl = 0.6 + 0.4 * out

        var path = Path()
        path.move(to: p(50, 130))
        // Belly, left side, up to the left tongue.
        path.addCurve(to: p(6 - breath, 90), control1: p(16, 130), control2: p(4 - breath, 112))
        path.addCurve(to: p(lt.x, lt.y, lead: tl), control1: p(8 - breath, 70), control2: p(lt.x - 6, lt.y + 18, lead: tl))
        // Down into the notch, then up the long main tongue to the tip.
        path.addCurve(to: p(nl.x, nl.y), control1: p(lt.x + 6, lt.y + 10, lead: tl), control2: p(nl.x - 6, nl.y - 4))
        path.addCurve(to: p(tip.x, tip.y, lead: 0.55), control1: p(nl.x + 2, 34, lead: 0.58), control2: p(tip.x - 14, tip.y + 20, lead: 0.55))
        // Down the right of the tip into the right notch, up to the right tongue.
        path.addCurve(to: p(nr.x, nr.y), control1: p(tip.x + 10, tip.y + 18, lead: 0.55), control2: p(nr.x - 2, nr.y - 14))
        path.addCurve(to: p(rt.x, rt.y, lead: tl), control1: p(nr.x + 4, nr.y - 6), control2: p(rt.x - 6, rt.y + 8, lead: tl))
        // Right side down and round the belly.
        path.addCurve(to: p(96 + breath, 88), control1: p(rt.x + 6, rt.y + 16, lead: tl), control2: p(98 + breath, 66))
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
