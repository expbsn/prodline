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

/// The brand green (Suica-card green) as a sky: deeper on top, a light haze at the bottom (make_store_art.swift).
func brandCanvas() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let hsb = { (s: CGFloat, b: CGFloat, a: CGFloat) in NSColor(hue: 0.345, saturation: s, brightness: b, alpha: a).usingColorSpace(.sRGB)!.cgColor }
    let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         colors: [hsb(0.76, 0.64, 1), hsb(0.66, 0.75, 1), hsb(0.34, 0.90, 1), hsb(0.14, 0.96, 1)] as CFArray,
                         locations: [0, 0.45, 0.8, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
    let haze = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [rgb(0xFFFFFF, 0.5), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(haze, startCenter: CGPoint(x: W * 0.18, y: -H * 0.05), startRadius: 0,
                           endCenter: CGPoint(x: W * 0.18, y: -H * 0.05), endRadius: W * 0.45, options: [])
    return ctx
}

func save(_ ctx: CGContext, _ name: String) {
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name + ".png"))
}

/// A window capture under a centered headline.
/// `brand`: the first frame, on the brand green with white type.
func windowFrame(_ file: String, shot: String, title: String, sub: String, glow: Int, brand: Bool = false) {
    let ctx = brand ? brandCanvas() : canvas(glow: glow)
    text(ctx, title, font: display(118, 680), color: brand ? rgb(0xFFFFFF) : rgb(0x1C1C1E), x: 0, top: 96, width: W, lineHeight: 128, align: .center)
    text(ctx, sub, font: ui(46, .medium), color: brand ? rgb(0xFFFFFF, 0.88) : rgb(0x6C6C70), x: 0, top: 246, width: W, lineHeight: 58, align: .center)
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

windowFrame("01-dash", shot: "dash.png", title: "Your week at a glance.", sub: "What's due, what's next and what just happened.", glow: 0x46B500, brand: true)
windowFrame("02-project", shot: "project.png", title: "Live numbers for every project.", sub: "From the services you already use.", glow: 0x2F6BFF)
windowFrame("03-plan", shot: "plan.png", title: "Every deadline in one place.", sub: "An agenda and a calendar across all your projects.", glow: 0xF5A623)
windowFrame("05-create", shot: "create.png", title: "Plan a build in a minute.", sub: "Name it, pick your rhythm, start.", glow: 0x46B500)

// 04: the top right corner of the desktop, zoomed in (3 px per point): the menu bar with Prodline's icon
// highlighted, its panel open, and the Prodline window behind.
do {
    let ctx = canvas(glow: 0x8E8E93)
    text(ctx, "One click away.", font: display(118, 680), color: rgb(0x1C1C1E), x: 0, top: 96, width: W, lineHeight: 128, align: .center)
    text(ctx, "Today's goals and your numbers, right in the menu bar.", font: ui(46, .medium), color: rgb(0x6C6C70), x: 0, top: 246, width: W, lineHeight: 58, align: .center)

    let screenW = W * 0.78, screenH = H - 360
    let screen = CGRect(x: (W - screenW) / 2, y: 0, width: screenW, height: screenH)   // bleeds off the bottom
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: rgb(0x000000, 0.22))
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.clip()

    // Neutral wallpaper.
    let wall = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(0xE6E6EA), rgb(0xCFCFD6), rgb(0xB9B9C2)] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(wall, start: CGPoint(x: screen.minX, y: screen.maxY), end: CGPoint(x: screen.maxX, y: screen.minY), options: [])

    let k: CGFloat = 3            // pixels per point at this zoom
    let barH = 24 * k
    let top = screen.maxY

    // The Prodline window behind, its sidebar and greeting in view (window captures are 2 px per point).
    let win = image("dash.png")
    let ww = CGFloat(win.width) * k / 2, wh = CGFloat(win.height) * k / 2
    let winRect = CGRect(x: screen.minX + 40 * k, y: top - barH - 22 * k - wh, width: ww, height: wh)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * k), blur: 30 * k, color: rgb(0x000000, 0.25))
    ctx.addPath(CGPath(roundedRect: winRect, cornerWidth: 10 * k, cornerHeight: 10 * k, transform: nil)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: winRect, cornerWidth: 10 * k, cornerHeight: 10 * k, transform: nil)); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(win, in: winRect)
    ctx.restoreGState()

    // Menu bar, right side: Prodline's icon (open), then the system items and the clock.
    ctx.setFillColor(rgb(0xF4F4F6, 0.82)); ctx.fill(CGRect(x: screen.minX, y: top - barH, width: screen.width, height: barH))
    ctx.setFillColor(rgb(0x000000, 0.08)); ctx.fill(CGRect(x: screen.minX, y: top - barH, width: screen.width, height: 1.5))
    let clock = NSAttributedString(string: "Tue 27 Oct  9:41", attributes: [.font: ui(13 * k, .medium), .foregroundColor: rgb(0x1C1C1E)])
    let clockLine = CTLineCreateWithAttributedString(clock)
    let clockW = CTLineGetTypographicBounds(clockLine, nil, nil, nil)
    var x = screen.maxX - 14 * k - clockW
    ctx.textPosition = CGPoint(x: x, y: top - barH + 7.5 * k)
    CTLineDraw(clockLine, ctx)
    func symbol(_ name: String, width: CGFloat) {
        x -= width + 12 * k
        let cfg = NSImage.SymbolConfiguration(pointSize: 13 * k, weight: .medium)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        let s = img.size, r = CGRect(x: x + (width - s.width) / 2, y: top - barH + (barH - s.height) / 2, width: s.width, height: s.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: r)
        NSGraphicsContext.restoreGraphicsState()
    }
    symbol("switch.2", width: 18 * k)
    symbol("magnifyingglass", width: 16 * k)
    symbol("wifi", width: 18 * k)
    symbol("battery.100percent", width: 26 * k)
    // Prodline, highlighted because its panel is open.
    x -= 22 * k + 12 * k
    let iconBox = CGRect(x: x - 5 * k, y: top - barH + 2.5 * k, width: 32 * k, height: barH - 5 * k)
    ctx.addPath(CGPath(roundedRect: iconBox, cornerWidth: 5 * k, cornerHeight: 5 * k, transform: nil))
    ctx.setFillColor(rgb(0x000000, 0.12)); ctx.fillPath()
    ctx.saveGState()
    ctx.setBlendMode(.multiply)
    ctx.draw(image("logo.png"), in: CGRect(x: iconBox.midX - 12 * k, y: iconBox.midY - 12 * k, width: 24 * k, height: 24 * k))
    ctx.restoreGState()

    // The panel, hanging from the icon (the snapshot is 3 px per point already).
    let panel = image("menu.png")
    let pw = CGFloat(panel.width), ph = CGFloat(panel.height)
    let rect = CGRect(x: min(iconBox.midX - pw * 0.5, screen.maxX - 10 * k - pw), y: top - barH - 6 * k - ph, width: pw, height: ph)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: rgb(0x000000, 0.3))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil)); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(panel, in: rect)
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil))
    ctx.setStrokeColor(rgb(0x000000, 0.12)); ctx.setLineWidth(1.5); ctx.strokePath()

    ctx.restoreGState()
    save(ctx, "04-menu-bar")
}
print("ok")
