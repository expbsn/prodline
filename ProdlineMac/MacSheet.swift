import SwiftUI
import AppKit

/// Sheets on the Mac: a size that fits a desktop, Esc closes, and a trackpad tick when one opens.
struct MacSheetFrame: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .frame(minWidth: width, idealWidth: width, minHeight: min(height, 480), idealHeight: height)
            .background {
                Button("") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0).allowsHitTesting(false)
            }
            .onAppear { Haptics.soft() }
    }
}

extension View {
    func macSheet(width: CGFloat, height: CGFloat) -> some View { modifier(MacSheetFrame(width: width, height: height)) }
}

/// The Prodline mark for the menu bar: drawn from the logo geometry as a template image, so macOS tints
/// it like every other menu bar icon.
enum MenuBarLogo {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let b = LogoGeometry.bounds
            let scale = min(rect.width / b.width, rect.height / b.height)
            ctx.translateBy(x: (rect.width - b.width * scale) / 2, y: (rect.height - b.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -b.minX, y: -b.minY)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(LogoGeometry.stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(LogoGeometry.main)
            for (a, b) in [LogoGeometry.downDash, LogoGeometry.leftDash] {
                ctx.move(to: a); ctx.addLine(to: b)
            }
            for p in [LogoGeometry.downDot, LogoGeometry.leftDot] {
                ctx.move(to: p); ctx.addLine(to: p)
            }
            ctx.strokePath()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
