import SwiftUI

/// What the streak looks like. The flame is kept whole (FlameShape, StreakOverlay); switch back here.
enum StreakLook {
    case flame, sprout
    static let current: StreakLook = .sprout

    var color: Color { self == .flame ? Theme.flame : Theme.brand }
}

extension Theme {
    /// A dried-out sprout: no streak today.
    static let dry = Color(light: 0xB59A6E, dark: 0x8C785A)
}

/// Prodline's seedling: a stem out of the soil and two leaves at its top, drawn in a 120 × 92 box.
/// `grow` raises the stem first and then opens the leaves (around 0.4 a shoot with a closed bud, 1 full,
/// a little past 1 while it springs up). `wilt` dries it out: the stem bows over, the leaves hang and shrivel.
/// `time` and `life` sway it in a breeze (life 0 = still, for badges).
struct SproutShape: Shape {
    enum Part { case stem, leaves, veins }
    var part: Part
    var grow: Double = 1
    var wilt: Double = 0
    var time: Double = 0
    var life: Double = 0
    var stemWidth: Double = 8

    static let aspect: CGFloat = 120 / 92

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(grow, AnimatablePair(wilt, time)) }
        set { grow = newValue.first; wilt = newValue.second.first; time = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 120, sy = rect.height / 92
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        let stemK = grow >= 1 ? grow : min(1, grow / 0.6)
        let leafK = grow >= 1 ? grow : max(0, (grow - 0.3) / 0.7)
        let sway = sin(time * 1.3) * life
        let h = 46 * stemK
        let top = (x: 58 + 3 * sway * stemK + 9 * wilt * stemK, y: 88 - h + 7 * wilt * stemK)

        var path = Path()
        if part == .stem {
            var stem = Path()
            stem.move(to: p(58, 88))
            stem.addCurve(to: p(top.x, top.y), control1: p(58, 88 - h * 0.45),
                          control2: p(58 + 1.5 * sway, 88 - h * (0.85 + 0.12 * wilt)))
            return stem.strokedPath(StrokeStyle(lineWidth: stemWidth * sx * (0.55 + 0.45 * min(1, stemK)), lineCap: .round))
        }
        guard leafK > 0 else { return path }
        // Closed, the two leaves press together into a bud pointing up; open, they spread left and right.
        let o = min(1, leafK), open = o * o * (3 - 2 * o)
        let leaves = [(closed: -100.0, opened: -158.0, droop: -205.0, length: 46.0, width: 18.0, phase: 0.0),
                      (closed: -80.0, opened: -28.0, droop: 38.0, length: 54.0, width: 21.0, phase: 2.1)]
        for l in leaves {
            let angle = l.closed + (l.opened - l.closed) * open
            let deg = angle + (l.droop - angle) * wilt + 5 * sin(time * 1.7 + l.phase) * life
            let th = deg * .pi / 180
            let d = (x: cos(th), y: sin(th)), n = (x: -sin(th), y: cos(th))
            let len = l.length * leafK * (1 - 0.12 * wilt)
            let wid = l.width * pow(leafK, 1.3) * (1 - 0.3 * wilt)
            /// `u` along the leaf from its base, `v` across it.
            func at(_ u: Double, _ v: Double) -> CGPoint {
                p(top.x + d.x * len * u + n.x * v, top.y + d.y * len * u + n.y * v)
            }
            if part == .veins {
                path.move(to: at(0.14, 0))
                path.addQuadCurve(to: at(0.72, -wid * 0.08), control: at(0.42, wid * 0.12))
            } else {
                path.move(to: at(0, 0))
                path.addCurve(to: at(1, 0), control1: at(0.22, wid), control2: at(0.72, wid * 0.85))
                path.addCurve(to: at(0, 0), control1: at(0.7, -wid * 0.7), control2: at(0.25, -wid * 0.75))
                path.closeSubpath()
            }
        }
        return path
    }
}

/// The small still sprout for badges: green when today counts, dried out and hanging when it doesn't.
struct SproutMark: View {
    var lit: Bool

    var body: some View {
        let wilt = lit ? 0.0 : 1.0
        ZStack {
            SproutShape(part: .stem, wilt: wilt, stemWidth: 11).fill(lit ? Color(hex: 0x23933A) : Theme.dry)
            SproutShape(part: .leaves, wilt: wilt).fill(lit ? Theme.brand : Theme.dry)
            SproutShape(part: .veins, wilt: wilt)
                .stroke(.white.opacity(lit ? 0.5 : 0.3), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .aspectRatio(SproutShape.aspect, contentMode: .fit)
        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: lit)
    }
}

/// The streak's symbol next to a number (stats, widgets, the Mac sidebar).
struct StreakSymbol: View {
    var lit = true
    var size: CGFloat

    var body: some View {
        switch StreakLook.current {
        case .flame:
            Image(systemName: "flame.fill").font(.system(size: size)).foregroundStyle(lit ? Theme.flame : Theme.secondary)
        case .sprout:
            SproutMark(lit: lit).frame(width: size * 1.35)
        }
    }
}

/// The streak sprout as a chunky cartoon object: a mound of soil, a stem and two glossy leaves on a dark
/// extruded body, swaying a little. `grow` takes it from a seed to the full sprout; `bright` from pale in
/// the dark to fresh green with a glow.
struct GrowingSprout: View {
    var grow: Double
    var bright: Double
    var width: CGFloat = 180
    /// When it came up; the sway eases in from then.
    var alive: Date = .distantPast
    /// How strong the halo is once grown (1 = the full streak-moment glow).
    var glow: Double = 1

    var body: some View {
        let s = width / 180
        let boxH = width / SproutShape.aspect
        let soilW = width * 0.6, soilH = width * 0.17
        TimelineView(.animation) { tl in
            let since = max(0, tl.date.timeIntervalSince(alive))
            let life = min(1, 0.3 + since / 1.2)
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                ZStack {
                    ForEach((1...7).reversed(), id: \.self) { i in
                        let dx = CGFloat(i) * 0.6 * s, dy = CGFloat(i) * 1.1 * s
                        SproutShape(part: .stem, grow: grow, time: t, life: life, stemWidth: 10).fill(Color(hex: 0x15602A)).offset(x: dx, y: dy)
                        SproutShape(part: .leaves, grow: grow, time: t, life: life).fill(Color(hex: 0x15602A)).offset(x: dx, y: dy)
                    }
                    SproutShape(part: .stem, grow: grow, time: t, life: life, stemWidth: 10)
                        .fill(LinearGradient(colors: [Color(hex: 0x56C94C), Color(hex: 0x23933A)], startPoint: .top, endPoint: .bottom))
                    SproutShape(part: .leaves, grow: grow, time: t, life: life)
                        .fill(LinearGradient(colors: [Color(hex: 0x9BE86A), Color(hex: 0x30B03C)], startPoint: .top, endPoint: .bottom))
                    SproutShape(part: .veins, grow: grow, time: t, life: life)
                        .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                }
                .frame(width: width, height: boxH)
                // The stem's foot (y 88 of 92) sits in the middle of the soil.
                .offset(y: -(soilH * 0.45 - boxH * 4 / 92))
                Soil(scale: s)
                    .frame(width: soilW, height: soilH)
                    .offset(x: -width * 2 / 120)
            }
            .frame(width: width, height: boxH + soilH * 0.45, alignment: .bottom)
            // Pale and dim while it's a shoot in the dark; fresh green once it's grown.
            .saturation(0.35 + 0.65 * bright)
            .brightness(-0.22 * (1 - bright))
        }
        .shadow(color: Theme.brand.opacity(0.55 * bright * glow), radius: 14 * s)
        .shadow(color: Theme.brand.opacity(0.3 * bright * glow), radius: 40 * s)
    }
}

/// A chunky mound of soil with a couple of pebbles, the sprout's foot hidden in it.
private struct Soil: View {
    let scale: CGFloat

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Ellipse().fill(Color(hex: 0x3E2614)).offset(y: 5 * scale)
                Ellipse().fill(LinearGradient(colors: [Color(hex: 0x8C5B33), Color(hex: 0x684122)], startPoint: .top, endPoint: .bottom))
                Ellipse().fill(Color(hex: 0x553520)).frame(width: w * 0.22, height: h * 0.2).offset(x: w * 0.02, y: -h * 0.16)
                Circle().fill(Color(hex: 0xA77A50)).frame(width: 7 * scale).offset(x: -w * 0.3, y: h * 0.08)
                Circle().fill(Color(hex: 0xA77A50)).frame(width: 5 * scale).offset(x: w * 0.28, y: h * 0.14)
                Capsule().fill(.white.opacity(0.18)).frame(width: w * 0.22, height: 3 * scale).offset(x: -w * 0.2, y: -h * 0.28)
            }
        }
    }
}
