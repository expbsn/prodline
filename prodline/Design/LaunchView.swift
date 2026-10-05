import SwiftUI
import UIKit
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
    static let main: CGPath = {
        let p = CGMutablePath()
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
/// Built from Core Animation layers so the render server plays it even while the main thread
/// is busy starting up (SwiftData, CloudKit, first refresh).
struct LaunchView: UIViewRepresentable {
    var onFinish: () -> Void

    func makeUIView(context: Context) -> LaunchAnimationView {
        let v = LaunchAnimationView()
        v.onFinish = onFinish
        return v
    }
    func updateUIView(_ uiView: LaunchAnimationView, context: Context) {}
}

final class LaunchAnimationView: UIView {
    var onFinish: (() -> Void)?
    private var started = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Theme.background)
        isAccessibilityElement = true
        accessibilityLabel = "Prodline"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !started, bounds.width > 0, bounds.height > 0 else { return }
        started = true
        let script = LaunchScript(size: bounds.size)
        // A short lead so layers are committed before the first beat; haptics share the same clock.
        let lead = 0.08
        build(script, base: CACurrentMediaTime() + lead)
        LaunchHaptics.play(script.haptics, delay: lead)
        DispatchQueue.main.asyncAfter(deadline: .now() + lead + script.total) { [weak self] in self?.onFinish?() }
    }

    private func build(_ s: LaunchScript, base: CFTimeInterval) {
        let ink = UIColor(Theme.ink).cgColor
        let width = LogoGeometry.stroke * s.scale
        var transform = s.transform

        func shape(_ path: CGPath) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.path = path
            l.fillColor = nil
            l.strokeColor = ink
            l.lineWidth = width
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
            return l
        }
        func animate(_ l: CALayer, _ a: CAAnimation, at t: Double, key: String) {
            a.beginTime = base + t
            a.fillMode = .backwards
            l.add(a, forKey: key)
        }

        for piece in s.pieces {
            switch piece.kind {
            case .dot(let p):
                let r = width / 2
                let l = CAShapeLayer()
                l.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
                l.fillColor = ink
                l.position = s.screen(p)
                layer.addSublayer(l)
                let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                pop.values = [0, 1.25, 1]
                pop.keyTimes = [0, 0.6, 1]
                pop.duration = piece.duration
                pop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
                animate(l, pop, at: piece.start, key: "pop")
                if let fade = piece.fadeAt { fadeOut(l, at: base + fade) }
            case .line(let a, let b):
                let path = CGMutablePath()
                path.move(to: s.screen(a)); path.addLine(to: s.screen(b))
                let l = shape(path)
                let grow = CABasicAnimation(keyPath: "strokeEnd")
                grow.fromValue = 0; grow.toValue = 1
                grow.duration = piece.duration
                animate(l, grow, at: piece.start, key: "grow")
                // strokeEnd 0 still paints a round cap, so stay hidden until the line starts.
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 0; show.toValue = 0; show.duration = 0.001
                animate(l, show, at: piece.start, key: "show")
            case .carve:
                guard let path = LogoGeometry.main.copy(using: &transform) else { continue }
                let l = shape(path)
                let carve = CABasicAnimation(keyPath: "strokeEnd")
                carve.fromValue = 0; carve.toValue = 1
                carve.duration = piece.duration
                carve.timingFunction = CAMediaTimingFunction(name: .linear)
                animate(l, carve, at: piece.start, key: "carve")
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 0; show.toValue = 0; show.duration = 0.001
                animate(l, show, at: piece.start, key: "show")
                addSparks(following: path, start: base + piece.start, duration: piece.duration)
            }
        }
    }

    private func fadeOut(_ l: CALayer, at time: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1; a.toValue = 0
        a.duration = 0.18
        a.beginTime = time
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        l.add(a, forKey: "fade")
    }

    /// Grinder sparks thrown off the carving tip: short glowing streaks flung up and sideways that arc down
    /// under gravity, turning to follow their path and shrinking as they cool. Each is its own tiny layer
    /// with a precomputed trajectory, so the render server plays them like the rest of the splash.
    private func addSparks(following path: CGPath, start: CFTimeInterval, duration: Double) {
        let samples = LaunchScript.sample(path, count: 120)
        guard samples.count > 1 else { return }
        var rng = LaunchScript.SplitMix(seed: 11)
        let colors = [UIColor(red: 1, green: 0.55, blue: 0.05, alpha: 1),
                      UIColor(red: 1, green: 0.76, blue: 0.18, alpha: 1),
                      UIColor(red: 1, green: 0.38, blue: 0.08, alpha: 1)]
        let count = 110
        let gravity: CGFloat = 900
        for j in 0..<count {
            let f = Double(j) / Double(count - 1)
            let origin = samples[min(samples.count - 1, Int(f * Double(samples.count - 1)))]
            let angle = -CGFloat.pi / 2 + rng.next(-1.35, 1.35)
            let speed = rng.next(140, 330)
            let v = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            let life = Double(rng.next(0.28, 0.55))

            let arc = CGMutablePath()
            arc.move(to: origin)
            for k in 1...10 {
                let t = CGFloat(life) * CGFloat(k) / 10
                arc.addLine(to: CGPoint(x: origin.x + v.dx * t, y: origin.y + v.dy * t + 0.5 * gravity * t * t))
            }

            let spark = CALayer()
            let length = rng.next(5, 10)
            spark.bounds = CGRect(x: 0, y: 0, width: length, height: 2)
            spark.cornerRadius = 1
            spark.backgroundColor = colors[j % colors.count].cgColor
            spark.opacity = 0
            spark.position = origin
            layer.addSublayer(spark)

            let begin = start + duration * f
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = arc
            fly.rotationMode = .rotateAuto
            fly.calculationMode = .linear
            let shine = CAKeyframeAnimation(keyPath: "opacity")
            shine.values = [1, 1, 0]
            shine.keyTimes = [0, 0.55, 1]
            let cool = CABasicAnimation(keyPath: "transform.scale.x")
            cool.fromValue = 1.2
            cool.toValue = 0.3
            let group = CAAnimationGroup()
            group.animations = [fly, shine, cool]
            group.duration = life
            group.beginTime = begin
            group.isRemovedOnCompletion = true
            spark.add(group, forKey: "spark")
        }
    }

}

/// Timing and placement of every beat of the splash, shared by the layers and the haptics.
struct LaunchScript {
    enum Kind { case dot(CGPoint), line(CGPoint, CGPoint), carve }
    struct Piece { let kind: Kind; let start: Double; let duration: Double; var fadeAt: Double? = nil }
    enum Haptic { case dot(Double, strong: Bool), carve(Double, duration: Double) }

    private(set) var pieces: [Piece] = []
    private(set) var haptics: [Haptic] = []
    private(set) var total: Double = 0
    let scale: CGFloat
    let origin: CGPoint
    static let carveDuration = 0.85

    private static let step = 0.06        // between dots
    private static let trainLife = 0.3    // how long a passing dot stays before fading

    var transform: CGAffineTransform { CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale) }
    func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }

    /// One beat: dots pop in, dashes draw; passing dots (`extra`) fade again like a moving train.
    private mutating func add(_ kind: Kind, at time: Double, extra: Bool, fadeAt: Double) {
        switch kind {
        case .line: pieces.append(Piece(kind: kind, start: time, duration: 0.07))
        default: pieces.append(Piece(kind: kind, start: time, duration: 0.16, fadeAt: extra ? fadeAt : nil))
        }
        haptics.append(.dot(time, strong: !extra))
    }

    /// Start times for `count` beats spread with an ease-in-out curve: slow off the line, quick in the middle,
    /// settling at the end. Same average pace as a fixed step, just distributed.
    /// Evenly spaced points along a path (by length), for placing sparks along the carve.
    static func sample(_ path: CGPath, count: Int) -> [CGPoint] {
        let p = Path(path)
        return (0..<count).compactMap { i in p.trimmedPath(from: 0, to: Double(i) / Double(count - 1)).currentPoint }
    }

    /// Small deterministic generator so the splash looks the same every launch.
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return lo + (hi - lo) * CGFloat(Double(z >> 11) / Double(UInt64(1) << 53))
        }
    }

    /// A passing dot fades once four more have appeared, so the train keeps its length at any speed.
    static func trainFade(_ times: [Double], _ i: Int) -> Double {
        i + 4 < times.count ? times[i + 4] : (times.last ?? 0) + trainLife
    }

    static func eased(count: Int, from t0: Double) -> [Double] {
        guard count > 1 else { return [t0] }
        let span = Double(count - 1) * step * 1.25
        return (0..<count).map { i in
            let x = Double(i) / Double(count - 1)
            let e = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
            return t0 + span * e
        }
    }

    init(size: CGSize, markWidth: CGFloat = 150) {
        let g = LogoGeometry.self
        scale = markWidth / g.bounds.width
        origin = CGPoint(x: size.width / 2 - g.bounds.midX * scale, y: size.height / 2 - g.bounds.midY * scale)

        var t = 0.1
        // Incoming: a train of dots rising from below the screen edge into the mark's own dot and dash.
        // Dotted phases ease in and out; the carve in between runs at a constant speed.
        var below: [CGPoint] = []
        var y = g.downDot.y + g.spacing
        while origin.y + y * scale < size.height + g.stroke * scale { below.append(CGPoint(x: g.stemX, y: y)); y += g.spacing }
        let incoming: [Kind] = below.reversed().map { .dot($0) } + [.dot(g.downDot), .line(g.downDash.from, g.downDash.to)]
        let inTimes = Self.eased(count: incoming.count, from: t)
        for (i, kind) in incoming.enumerated() {
            add(kind, at: inTimes[i], extra: i < below.count, fadeAt: Self.trainFade(inTimes, i))
        }
        t = (inTimes.last ?? t) + Self.step + 0.02

        // Carve the letter.
        pieces.append(Piece(kind: .carve, start: t, duration: Self.carveDuration))
        haptics.append(.carve(t, duration: Self.carveDuration))
        t += Self.carveDuration + 0.02

        // Leaving: dash, the mark's dot, then a train running off the left edge.
        var left: [CGPoint] = []
        var x = g.leftDot.x - g.spacing
        while origin.x + x * scale > -g.stroke * scale { left.append(CGPoint(x: x, y: g.barY)); x -= g.spacing }
        let outgoing: [Kind] = [.line(g.leftDash.from, g.leftDash.to), .dot(g.leftDot)] + left.map { .dot($0) }
        let outTimes = Self.eased(count: outgoing.count, from: t)
        for (i, kind) in outgoing.enumerated() {
            add(kind, at: outTimes[i], extra: i >= 2, fadeAt: Self.trainFade(outTimes, i))
        }
        t = outTimes.last ?? t
        total = t + Self.trainLife + 0.55
    }
}

/// One Core Haptics pattern for the whole splash so taps stay locked to the drawing.
enum LaunchHaptics {
    private static var engine: CHHapticEngine?

    static func play(_ events: [LaunchScript.Haptic], delay: Double) {
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
            try player.start(atTime: engine.currentTime + delay)
            self.engine = engine
        } catch {
            // Haptics are a garnish; the splash plays without them.
        }
    }
}
