// Composes the Mac App Store screenshots (2880 x 1800): a headline above the real window, and the menu bar
// panel under a menu bar for the fourth one.
// swiftc -O design/make_mac_frames.swift -o /tmp/macframes && /tmp/macframes <shots dir> marketing/app-store/mac
// Shots: the Mac app with -PRODLINE_STORE YES (window captures, plus menu.png and logo.png from the snapshot writer).
import AppKit
import CoreText

let args = CommandLine.arguments
let shots = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "prodline/fonts/AfacadFlux-VariableFont_slnt,wght.ttf") as CFURL, .process, nil)
let size = CGSize(width: 2880, height: 1800), W = size.width, H = size.height

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func display(_ size: CGFloat, _ weight: CGFloat) -> CTFont {
    let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: "AfacadFlux-Regular",
                                                  kCTFontVariationAttribute: [0x77676874: weight]] as CFDictionary)
    return CTFontCreateWithFontDescriptor(d, size, nil)
}
func ui(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont { NSFont.systemFont(ofSize: size, weight: weight) as CTFont }
func image(_ name: String) -> CGImage {
    NSImage(contentsOf: shots.appendingPathComponent(name))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

/// Wrapped text in `rect` (y from the top); returns the bottom.
@discardableResult
func text(_ ctx: CGContext, _ s: String, font: CTFont, color: CGColor, x: CGFloat, top: CGFloat, width: CGFloat,
          lineHeight: CGFloat, align: NSTextAlignment) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.minimumLineHeight = lineHeight; para.maximumLineHeight = lineHeight
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    let setter = CTFramesetterCreateWithAttributedString(attr)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: 10_000), nil)
    let rect = CGRect(x: x, y: H - top - ceil(fit.height), width: width, height: ceil(fit.height))
    CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil), ctx)
    return top + ceil(fit.height)
}

func canvas(glow: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(0xF2F2F5)); ctx.fill(CGRect(origin: .zero, size: size))
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [rgb(glow, 0.26), rgb(glow, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: W / 2, y: H * 0.4), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H * 0.4), endRadius: W * 0.62, options: [])
    return ctx
}

func save(_ ctx: CGContext, _ name: String) {
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name + ".png"))
}

/// A window capture under a centered headline.
func windowFrame(_ file: String, shot: String, title: String, sub: String, glow: Int) {
    let ctx = canvas(glow: glow)
    text(ctx, title, font: display(118, 680), color: rgb(0x1C1C1E), x: 0, top: 96, width: W, lineHeight: 128, align: .center)
    text(ctx, sub, font: ui(46, .medium), color: rgb(0x6C6C70), x: 0, top: 246, width: W, lineHeight: 58, align: .center)
    let win = image(shot)
    let w = W * 0.78, h = w * CGFloat(win.height) / CGFloat(win.width)
    let rect = CGRect(x: (W - w) / 2, y: H - 360 - h, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: rgb(0x000000, 0.22))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(win, in: rect)
    ctx.restoreGState()
    save(ctx, file)
}

windowFrame("01-dash", shot: "dash.png", title: "Your week at a glance.", sub: "What's due, what's next and what just happened.", glow: 0x46B500)
windowFrame("02-project", shot: "project.png", title: "Live numbers for every project.", sub: "From the services you already use.", glow: 0x2F6BFF)
windowFrame("03-plan", shot: "plan.png", title: "Every deadline in one place.", sub: "An agenda and a calendar across all your projects.", glow: 0xF5A623)
windowFrame("05-create", shot: "create.png", title: "Plan a build in a minute.", sub: "Name it, pick your rhythm, start.", glow: 0x46B500)

// 04: the menu bar panel on a desktop.
do {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let wall = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(0x7FA7FF), rgb(0xB49BFF), rgb(0xFFC9A8)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(wall, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    // Menu bar.
    let barH: CGFloat = 66
    ctx.setFillColor(rgb(0xFFFFFF, 0.55)); ctx.fill(CGRect(x: 0, y: H - barH, width: W, height: barH))
    let iconX = W - 520
    ctx.setFillColor(rgb(0x000000, 0.12))
    ctx.addPath(CGPath(roundedRect: CGRect(x: iconX - 14, y: H - barH + 9, width: 76, height: barH - 18), cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.fillPath()
    ctx.saveGState()
    ctx.setBlendMode(.multiply)
    ctx.draw(image("logo.png"), in: CGRect(x: iconX - 4, y: H - barH + 6, width: 56, height: 56))
    ctx.restoreGState()
    let clock = NSAttributedString(string: "Tue 27 Oct  9:41", attributes: [.font: ui(30, .semibold), .foregroundColor: rgb(0x1C1C1E)])
    ctx.textPosition = CGPoint(x: W - 300, y: H - barH + 22)
    CTLineDraw(CTLineCreateWithAttributedString(clock), ctx)
    // Panel under the icon.
    let panel = image("menu.png")
    let pw: CGFloat = 900, ph = pw * CGFloat(panel.height) / CGFloat(panel.width)
    let rect = CGRect(x: iconX + 24 - pw * 0.72, y: H - barH - 22 - ph, width: pw, height: ph)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 70, color: rgb(0x000000, 0.28))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil)); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(panel, in: rect)
    ctx.restoreGState()
    // Headline on the left.
    let bottom = text(ctx, "One click away.", font: display(150, 680), color: rgb(0x1C1C1E), x: 200, top: 620, width: 1150, lineHeight: 160, align: .left)
    text(ctx, "Today's goals and your numbers, right in the menu bar.", font: ui(52, .medium), color: rgb(0x1C1C1E, 0.7),
         x: 200, top: bottom + 40, width: 1050, lineHeight: 66, align: .left)
    save(ctx, "04-menu-bar")
}
print("ok")
