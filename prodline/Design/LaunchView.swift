import SwiftUI

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

/// The cold-start splash: the white mark on the brand green (where the system launch screen already put it,
/// so the hand-over is seamless) and a quiet trademark line. Green in light and dark mode alike. RootView holds it briefly, then blurs it away into the app.
/// (The animated splash it replaced lives in Design/Archive/LaunchAnimation.swift.)
struct LaunchSplash: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Image("LaunchMark").resizable().scaledToFit()
                .frame(width: 96, height: 96)
        }
        .overlay(alignment: .bottom) {
            Text("Prodline™")
                .font(.ui(12, .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 44)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Prodline")
    }
}

enum LaunchGate {
    static let replay = Notification.Name("prodline.replayLaunch")
    static var shouldShow: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "PRODLINE_NOLAUNCH") { return false }
        #endif
        // The splash is still now, so Reduce Motion doesn't need to skip it.
        return true
    }
}
