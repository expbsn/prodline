import SwiftUI
import CoreHaptics

/// The Prodline mark in 1024-unit icon space (y down). Mirrors design/make_logo.swift; keep both in sync.
enum LogoGeometry {
    static let stroke: CGFloat = 100
    /// Visual bounds of the full mark including round caps.
    static let bounds = CGRect(x: 56, y: 140, width: 850, height: 836)
    static let stemX: CGFloat = 490
    static let barY: CGFloat = 490
    /// Rhythm of the dotted line (dot center to dot center).
    static let spacing: CGFloat = 160

    /// Stem up from the bottom, around the bowl, out along the crossbar: one continuous stroke.
    static let main: Path = {
        var p = Path()
        p.move(to: CGPoint(x: stemX, y: 630))
        p.addLine(to: CGPoint(x: stemX, y: 390))
        p.addCurve(to: CGPoint(x: 672, y: 190), control1: CGPoint(x: stemX, y: 250), control2: CGPoint(x: 552, y: 190))
        p.addCurve(to: CGPoint(x: 856, y: 342), control1: CGPoint(x: 792, y: 190), control2: CGPoint(x: 856, y: 262))
        p.addCurve(to: CGPoint(x: 700, y: barY), control1: CGPoint(x: 856, y: 430), control2: CGPoint(x: 792, y: barY))
        p.addLine(to: CGPoint(x: 402, y: barY))
        return p
    }()
    static let downDot = CGPoint(x: stemX, y: 926)
    static let downDash = (from: CGPoint(x: stemX, y: 790), to: CGPoint(x: stemX, y: 766))
    static let leftDash = (from: CGPoint(x: 266, y: barY), to: CGPoint(x: 242, y: barY))
    static let leftDot = CGPoint(x: 106, y: barY)
}

/// Cold-start splash: a dotted line rises from the bottom, carves the "p" and leaves to the left.
struct LaunchView: View {
    var onFinish: () -> Void
    @State private var script: LaunchScript?
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                Canvas { gc, _ in
                    script?.draw(in: &gc, t: tl.date.timeIntervalSince(start))
                }
            }
            .onAppear {
                let s = LaunchScript(size: geo.size)
                script = s
                start = .now
                LaunchHaptics.play(s.haptics)
                Task {
                    try? await Task.sleep(for: .seconds(s.total))
                    onFinish()
                }
            }
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .accessibilityLabel("Prodline")
    }
}

struct LaunchScript {
    enum Kind { case dot(CGPoint), line(CGPoint, CGPoint), carve }
    struct Piece { let kind: Kind; let start: Double; let duration: Double; var fadeAt: Double? = nil }
    struct Particle { let at: Double; let tip: CGPoint; let velocity: CGVector; let size: CGFloat }
    enum Haptic { case dot(Double, strong: Bool), carve(Double, duration: Double) }

    private(set) var pieces: [Piece] = []
    private(set) var particles: [Particle] = []
    private(set) var haptics: [Haptic] = []
    private(set) var total: Double = 0
    private let scale: CGFloat
    private let origin: CGPoint
    private let carveStart: Double
    static let carveDuration = 0.85

    private static let step = 0.06        // between dots
    private static let trainLife = 0.3    // how long a passing dot stays before fading
    private static let particleLife = 0.7

    init(size: CGSize, markWidth: CGFloat = 150) {
        let g = LogoGeometry.self
        scale = markWidth / g.bounds.width
        origin = CGPoint(x: size.width / 2 - g.bounds.midX * scale, y: size.height / 2 - g.bounds.midY * scale)
        let s = scale, o = origin
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: o.x + p.x * s, y: o.y + p.y * s) }

        var t = 0.15
        // Incoming: a train of dots rising from below the screen edge to the mark's own dot.
        var below: [CGPoint] = []
        var y = g.downDot.y + g.spacing
        while screen(CGPoint(x: 0, y: y)).y < size.height + g.stroke * s { below.append(CGPoint(x: g.stemX, y: y)); y += g.spacing }
        for p in below.reversed() {
            pieces.append(Piece(kind: .dot(p), start: t, duration: 0.16, fadeAt: t + Self.trainLife))
            haptics.append(.dot(t, strong: false))
            t += Self.step
        }
        pieces.append(Piece(kind: .dot(g.downDot), start: t, duration: 0.16))
        haptics.append(.dot(t, strong: true)); t += Self.step
        pieces.append(Piece(kind: .line(g.downDash.from, g.downDash.to), start: t, duration: 0.07))
        haptics.append(.dot(t, strong: true)); t += Self.step + 0.02

        // Carve the letter.
        carveStart = t
        pieces.append(Piece(kind: .carve, start: t, duration: Self.carveDuration))
        haptics.append(.carve(t, duration: Self.carveDuration))
        let samples = Self.sample(g.main, count: 200)
        var rng = SplitMix(seed: 7)
        let count = 90
        for j in 0..<count {
            let f = Double(j) / Double(count - 1)
            let tip = samples[min(samples.count - 1, Int(Self.ease(f) * Double(samples.count - 1)))]
            let jitter = CGPoint(x: tip.x + rng.next(-38, 38), y: tip.y + rng.next(-38, 38))
            let angle = rng.next(0, 2 * .pi), speed = rng.next(18, 64)
            particles.append(Particle(at: t + Self.carveDuration * f, tip: screen(jitter),
                                      velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                      size: rng.next(1.2, 2.8)))
        }
        t += Self.carveDuration + 0.02

        // Leaving: dash, the mark's dot, then a train running off the left edge.
        pieces.append(Piece(kind: .line(g.leftDash.from, g.leftDash.to), start: t, duration: 0.07))
        haptics.append(.dot(t, strong: true)); t += Self.step
        pieces.append(Piece(kind: .dot(g.leftDot), start: t, duration: 0.16))
        haptics.append(.dot(t, strong: true)); t += Self.step
        var x = g.leftDot.x - g.spacing
        while screen(CGPoint(x: x, y: 0)).x > -g.stroke * s {
            pieces.append(Piece(kind: .dot(CGPoint(x: x, y: g.barY)), start: t, duration: 0.16, fadeAt: t + Self.trainLife))
            haptics.append(.dot(t, strong: false))
            t += Self.step; x -= g.spacing
        }
        total = t + Self.trainLife + 0.55
    }

    func draw(in gc: inout GraphicsContext, t: Double) {
        let s = scale
        let ink = GraphicsContext.Shading.color(Theme.ink)
        let style = StrokeStyle(lineWidth: LogoGeometry.stroke * s, lineCap: .round, lineJoin: .round)
        let toScreen = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: s, y: s)
        func screen(_ p: CGPoint) -> CGPoint { p.applying(toScreen) }

        for piece in pieces where t >= piece.start {
            let f = min(1, (t - piece.start) / piece.duration)
            var c = gc
            if let fade = piece.fadeAt {
                let a = 1 - (t - fade) / 0.18
                if a <= 0 { continue }
                c.opacity = min(1, a)
            }
            switch piece.kind {
            case .dot(let p):
                let r = LogoGeometry.stroke / 2 * s * Self.backOut(f)
                let q = screen(p)
                c.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: ink)
            case .line(let a, let b):
                let end = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                var path = Path(); path.move(to: screen(a)); path.addLine(to: screen(end))
                c.stroke(path, with: ink, style: style)
            case .carve:
                let path = LogoGeometry.main.trimmedPath(from: 0, to: Self.ease(f)).applying(toScreen)
                c.stroke(path, with: ink, style: style)
            }
        }

        // Specks thrown off the carving tip.
        for p in particles {
            let age = t - p.at
            guard age > 0, age < Self.particleLife else { continue }
            let a = CGFloat(age)
            let pos = CGPoint(x: p.tip.x + p.velocity.dx * a, y: p.tip.y + p.velocity.dy * a + 70 * a * a)
            var c = gc
            c.opacity = 0.55 * (1 - age / Self.particleLife)
            c.fill(Path(ellipseIn: CGRect(x: pos.x - p.size / 2, y: pos.y - p.size / 2, width: p.size, height: p.size)), with: ink)
        }
    }

    // MARK: Helpers

    static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    static func backOut(_ x: Double) -> Double {
        let c1 = 1.9, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    static func sample(_ path: Path, count: Int) -> [CGPoint] {
        (0..<count).map { i in path.trimmedPath(from: 0, to: Double(i) / Double(count - 1)).currentPoint ?? .zero }
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return lo + (hi - lo) * CGFloat(Double(z >> 11) / Double(1 << 53))
        }
    }
}

/// One Core Haptics pattern for the whole splash so taps stay locked to the drawing.
enum LaunchHaptics {
    private static var engine: CHHapticEngine?

    static func play(_ events: [LaunchScript.Haptic]) {
        guard AppSettings.haptics, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        var list: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        for e in events {
            switch e {
            case .dot(let t, let strong):
                list.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: strong ? 0.85 : 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: strong ? 0.75 : 0.9),
                ], relativeTime: t))
            case .carve(let t, let d):
                // A low rumble that swells around the bowl, with a fine grain on top.
                list.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
                ], relativeTime: t, duration: d))
                curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                    .init(relativeTime: 0, value: 0.35),
                    .init(relativeTime: d * 0.5, value: 1),
                    .init(relativeTime: d, value: 0.45),
                ], relativeTime: t))
                for i in stride(from: 0.0, to: d, by: 0.07) {
                    list.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                    ], relativeTime: t + i))
                }
            }
        }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: list, parameterCurves: curves))
            try player.start(atTime: CHHapticTimeImmediate)
            self.engine = engine
        } catch {
            // Haptics are a garnish; the splash plays without them.
        }
    }
}
