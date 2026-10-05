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
                carve.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
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

    /// Fine specks thrown off the carving tip: an emitter riding the path at the stroke's pace.
    private func addSparks(following path: CGPath, start: CFTimeInterval, duration: Double) {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 10, height: 10)
        emitter.birthRate = 0
        let cell = CAEmitterCell()
        cell.contents = Self.speck
        cell.color = UIColor(Theme.ink).withAlphaComponent(0.6).cgColor
        cell.birthRate = 120
        cell.lifetime = 0.6
        cell.lifetimeRange = 0.2
        cell.velocity = 40
        cell.velocityRange = 25
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 70
        cell.alphaSpeed = -1.6
        cell.scale = 0.5
        cell.scaleRange = 0.25
        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)

        let move = CAKeyframeAnimation(keyPath: "emitterPosition")
        move.path = path
        move.calculationMode = .paced
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.duration = duration
        move.beginTime = start
        move.fillMode = .both
        move.isRemovedOnCompletion = false
        emitter.add(move, forKey: "move")

        let rate = CAKeyframeAnimation(keyPath: "birthRate")
        rate.values = [1, 1, 0]
        rate.keyTimes = [0, 0.92, 1]
        rate.duration = duration
        rate.beginTime = start
        emitter.add(rate, forKey: "rate")
    }

    private static let speck: CGImage? = {
        UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 6, height: 6)).fill()
        }.cgImage
    }()
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

    init(size: CGSize, markWidth: CGFloat = 150) {
        let g = LogoGeometry.self
        scale = markWidth / g.bounds.width
        origin = CGPoint(x: size.width / 2 - g.bounds.midX * scale, y: size.height / 2 - g.bounds.midY * scale)

        var t = 0.1
        // Incoming: a train of dots rising from below the screen edge to the mark's own dot.
        var below: [CGPoint] = []
        var y = g.downDot.y + g.spacing
        while origin.y + y * scale < size.height + g.stroke * scale { below.append(CGPoint(x: g.stemX, y: y)); y += g.spacing }
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
        pieces.append(Piece(kind: .carve, start: t, duration: Self.carveDuration))
        haptics.append(.carve(t, duration: Self.carveDuration))
        t += Self.carveDuration + 0.02

        // Leaving: dash, the mark's dot, then a train running off the left edge.
        pieces.append(Piece(kind: .line(g.leftDash.from, g.leftDash.to), start: t, duration: 0.07))
        haptics.append(.dot(t, strong: true)); t += Self.step
        pieces.append(Piece(kind: .dot(g.leftDot), start: t, duration: 0.16))
        haptics.append(.dot(t, strong: true)); t += Self.step
        var x = g.leftDot.x - g.spacing
        while origin.x + x * scale > -g.stroke * scale {
            pieces.append(Piece(kind: .dot(CGPoint(x: x, y: g.barY)), start: t, duration: 0.16, fadeAt: t + Self.trainLife))
            haptics.append(.dot(t, strong: false))
            t += Self.step; x -= g.spacing
        }
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
