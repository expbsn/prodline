import SwiftUI

/// Prodline's own cartoon flame: a round belly, a tall tip leaning a little right, and a tongue on each side.
/// `time` makes it burn — the tip wavers, the tongues lick up and sway, the sides breathe — so it moves like
/// fire instead of an icon being scaled. `life` scales that motion (0 = a still flame, for badges).
struct FlameShape: Shape {
    var time: Double = 0
    var life: Double = 1

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(time, life) }
        set { time = newValue.first; life = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        // Designed in a 100 × 130 box, scaled to fit the rect.
        let sx = rect.width / 100, sy = rect.height / 130
        let t = time
        let a = life
        // A few unrelated sines per point read as organic flicker rather than a loop.
        func w(_ f1: Double, _ f2: Double, _ phase: Double) -> Double { (sin(t * f1 + phase) * 0.65 + sin(t * f2 + phase * 1.7) * 0.35) * a }
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }

        let tip = (x: 58 + 6 * w(4.1, 7.3, 0), y: 2 + 5 * abs(w(5.2, 9.1, 1)))
        let left = (x: 16 + 4 * w(5.6, 8.7, 2), y: 38 + 7 * w(6.3, 10.1, 3))
        let right = (x: 88 + 4 * w(6.1, 9.4, 4), y: 30 + 7 * w(5.8, 11.2, 5))
        let notchL = (x: 32 + 2 * w(4.4, 7.7, 6), y: 58 + 3 * w(5.1, 8.2, 7))
        let notchR = (x: 74 + 2 * w(4.8, 8.4, 8), y: 46 + 3 * w(5.5, 9.3, 9))
        let breath = 1.5 * w(3.2, 5.1, 10)

        var path = Path()
        path.move(to: p(50, 130))
        // Belly, left side, up to the left tongue.
        path.addCurve(to: p(6 - breath, 90), control1: p(16, 130), control2: p(4 - breath, 112))
        path.addCurve(to: p(left.x, left.y), control1: p(8 - breath, 70), control2: p(left.x - 6, left.y + 18))
        // Down into the notch, then up the long main tongue to the tip.
        path.addCurve(to: p(notchL.x, notchL.y), control1: p(left.x + 6, left.y + 10), control2: p(notchL.x - 6, notchL.y - 4))
        path.addCurve(to: p(tip.x, tip.y), control1: p(notchL.x + 2, 34), control2: p(tip.x - 14, tip.y + 20))
        // Down the right of the tip into the right notch, up to the right tongue.
        path.addCurve(to: p(notchR.x, notchR.y), control1: p(tip.x + 10, tip.y + 18), control2: p(notchR.x - 2, notchR.y - 14))
        path.addCurve(to: p(right.x, right.y), control1: p(notchR.x + 4, notchR.y - 6), control2: p(right.x - 6, right.y + 8))
        // Right side down and round the belly.
        path.addCurve(to: p(96 + breath, 88), control1: p(right.x + 6, right.y + 16), control2: p(98 + breath, 66))
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
