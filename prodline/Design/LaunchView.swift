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

/// The cold-start splash, shown only while something is actually loading: the mark, still, and a quiet
/// trademark line at the bottom. When everything is ready on the first frame the app opens straight in.
/// (The animated splash it replaced lives in Design/Archive/LaunchAnimation.swift.)
struct LaunchSplash: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Image("Mark").resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(Theme.ink)
                .frame(width: 96, height: 96)
        }
        .overlay(alignment: .bottom) {
            Text("Prodline™")
                .font(.ui(12, .medium))
                .tracking(1)
                .foregroundStyle(Theme.tertiary)
                .padding(.bottom, 10)
        }
        .accessibilityElement()
        .accessibilityLabel("Prodline, loading")
    }
}
