// The App Store header (21:9, 3840 x 1646) and search results asset (3:2, 3840 x 2560).
// swiftc -O design/make_creative_assets.swift -o /tmp/creative && /tmp/creative <cards dir> <iphone shots dir> marketing/app-store
// Cards: the Mac snapshot writer with -PRODLINE_STORE YES (card-<project>.png); shots: the simulator (dash.png, traction.png).
import AppKit
import CoreText

let args = CommandLine.arguments
let cards = URL(fileURLWithPath: args[1]), shots = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3])
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "prodline/fonts/AfacadFlux-VariableFont_slnt,wght.ttf") as CFURL, .process, nil)

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func display(_ size: CGFloat, _ weight: CGFloat) -> CTFont {
    let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: "AfacadFlux-Regular",
                                                  kCTFontVariationAttribute: [0x77676874: weight]] as CFDictionary)
    return CTFontCreateWithFontDescriptor(d, size, nil)
}
func image(_ url: URL) -> CGImage { NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
func context(_ w: CGFloat, _ h: CGFloat) -> CGContext {
    CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}
func glow(_ ctx: CGContext, _ hex: Int, _ alpha: CGFloat, at p: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [rgb(hex, alpha), rgb(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}
func text(_ ctx: CGContext, _ s: String, font: CTFont, color: CGColor, rect: CGRect, lineHeight: CGFloat, align: NSTextAlignment) {
    let para = NSMutableParagraphStyle()
    para.alignment = align; para.minimumLineHeight = lineHeight; para.maximumLineHeight = lineHeight
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    CTFrameDraw(CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attr), CFRange(), CGPath(rect: rect, transform: nil), nil), ctx)
}
func save(_ ctx: CGContext, _ name: String) {
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

// Header: the five project cards in a gentle arc under one line.
do {
    let W: CGFloat = 3840, H: CGFloat = 1646
    let ctx = context(W, H)
    ctx.setFillColor(rgb(0xF2F2F5)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    glow(ctx, 0x2F6BFF, 0.22, at: CGPoint(x: W / 2, y: H * 0.38), radius: 1500)
    glow(ctx, 0x46B500, 0.16, at: CGPoint(x: W * 0.25, y: H * 0.3), radius: 1100)
    glow(ctx, 0x8A45F5, 0.16, at: CGPoint(x: W * 0.75, y: H * 0.3), radius: 1100)
    text(ctx, "Finish what you start.", font: display(150, 680), color: rgb(0x1C1C1E),
         rect: CGRect(x: 0, y: H - 300, width: W, height: 200), lineHeight: 160, align: .center)
    // Outer cards first, so the center one sits on top.
    let order: [(String, CGFloat, CGFloat, CGFloat)] = [   // card, x offset, scale, rotation
        ("moonlog", -1400, 0.70, 9), ("side-shop", 1400, 0.70, -9),
        ("habit-hero", -745, 0.84, 5), ("pixel-quest", 745, 0.84, -5),
        ("tiny-invoice", 0, 1.0, 0),
    ]
    let baseH: CGFloat = 1080
    for (slug, dx, scale, deg) in order {
        let card = image(cards.appendingPathComponent("sv-card-\(slug).png"))
        let h = baseH * scale, w = h * CGFloat(card.width) / CGFloat(card.height)
        let cy = H * 0.37 - (1 - scale) * 160
        ctx.saveGState()
        ctx.translateBy(x: W / 2 + dx, y: cy)
        ctx.rotate(by: deg * .pi / 180)
        ctx.setShadow(offset: CGSize(width: 0, height: -40 * scale), blur: 110 * scale, color: rgb(0x000000, 0.25))
        ctx.interpolationQuality = .high
        ctx.draw(card, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }
    save(ctx, "header-21x9.png")
}

// Search results: one line, and the real screens in phone outlines.
do {
    let W: CGFloat = 3840, H: CGFloat = 2560
    let ctx = context(W, H)
    ctx.setFillColor(rgb(0xF2F2F5)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    glow(ctx, 0x2F6BFF, 0.26, at: CGPoint(x: W * 0.68, y: H * 0.5), radius: 1700)
    glow(ctx, 0x46B500, 0.16, at: CGPoint(x: W * 0.9, y: H * 0.8), radius: 1100)
    text(ctx, "Your side projects, on a deadline.", font: display(230, 680), color: rgb(0x1C1C1E),
         rect: CGRect(x: 240, y: H * 0.5 - 520, width: 1500, height: 1040), lineHeight: 236, align: .left)

    func phone(_ shot: String, center: CGPoint, height: CGFloat, deg: CGFloat) {
        let img = image(shots.appendingPathComponent(shot))
        let h = height, w = h * CGFloat(img.width) / CGFloat(img.height)
        let bezel: CGFloat = 36, radius = w * 0.135
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: deg * .pi / 180)
        let screen = CGRect(x: -w / 2, y: -h / 2, width: w, height: h), body = screen.insetBy(dx: -bezel, dy: -bezel)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -50), blur: 140, color: rgb(0x000000, 0.25))
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
        ctx.setFillColor(rgb(0x1C1C1E)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(img, in: screen)
        ctx.restoreGState()
    }
    phone("dash.png", center: CGPoint(x: 3190, y: H * 0.5 + 60), height: 2050, deg: -4)
    phone("traction.png", center: CGPoint(x: 2390, y: H * 0.5 - 40), height: 2150, deg: 3)
    save(ctx, "search-3x2.png")
}
print("ok")
