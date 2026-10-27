// Composes the App Store screenshots: a headline and subline above the real screen in a phone outline.
// swiftc -O design/make_store_frames.swift -o /tmp/frames && /tmp/frames <shots dir> marketing/app-store
// The shots come from the simulator with -PRODLINE_STORE YES (see marketing/app-store.md).
import AppKit
import CoreText

let args = CommandLine.arguments
let shots = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "prodline/fonts/AfacadFlux-VariableFont_slnt,wght.ttf") as CFURL, .process, nil)

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func display(_ size: CGFloat, _ weight: CGFloat) -> CTFont {
    let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: "AfacadFlux-Regular",
                                                  kCTFontVariationAttribute: [0x77676874: weight]] as CFDictionary)
    return CTFontCreateWithFontDescriptor(d, size, nil)
}
func ui(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont { NSFont.systemFont(ofSize: size, weight: weight) as CTFont }

/// Draws centered, wrapped text with its top at `top` (y measured from the top); returns the bottom.
@discardableResult
func text(_ ctx: CGContext, _ s: String, font: CTFont, color: CGColor, top: CGFloat, width: CGFloat, canvas: CGSize, lineHeight: CGFloat) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.minimumLineHeight = lineHeight; para.maximumLineHeight = lineHeight
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    let setter = CTFramesetterCreateWithAttributedString(attr)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: 10_000), nil)
    let rect = CGRect(x: (canvas.width - width) / 2, y: canvas.height - top - ceil(fit.height), width: width, height: ceil(fit.height))
    CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil), ctx)
    return top + ceil(fit.height)
}

struct Frame { let file: String, shot: String, title: String, sub: String, glow: Int, dark: Bool }

let frames = [
    Frame(file: "01-dash", shot: "dash", title: "Finish what you start.", sub: "Every side project on a short clock.", glow: 0x46B500, dark: false),
    Frame(file: "02-numbers", shot: "traction", title: "Numbers, on their own.", sub: "Revenue and visitors, by themselves.", glow: 0x2F6BFF, dark: false),
    Frame(file: "03-plan", shot: "plan", title: "A deadline for every step.", sub: "Every project, every checkpoint.", glow: 0xF5A623, dark: false),
    Frame(file: "04-services", shot: "picker", title: "25+ services, connected.", sub: "Your keys stay in your Keychain.", glow: 0x635BFF, dark: false),
    Frame(file: "05-decide", shot: "verdict", title: "Keep, pivot or kill.", sub: "Decide on numbers, not on a feeling.", glow: 0x8A45F5, dark: false),
    Frame(file: "06-widgets", shot: "board", title: "Always in sight.", sub: "Your next deadline on the Home Screen.", glow: 0x6A4CFF, dark: true),
]

for (size, folder) in [(CGSize(width: 1206, height: 2622), "iphone-6.1"), (CGSize(width: 1320, height: 2868), "iphone-6.9")] {
    let dir = out.appendingPathComponent(folder)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let W = size.width, H = size.height, k = W / 1206
    for f in frames {
        let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Background with a soft glow of the screen's color behind the phone.
        ctx.setFillColor(f.dark ? rgb(0x0B0B14) : rgb(0xF2F2F5)); ctx.fill(CGRect(origin: .zero, size: size))
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [rgb(f.glow, f.dark ? 0.55 : 0.30), rgb(f.glow, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: H * 0.42), startRadius: 0,
                               endCenter: CGPoint(x: W / 2, y: H * 0.42), endRadius: W * 0.95, options: [])

        let ink = f.dark ? rgb(0xF5F5F7) : rgb(0x1C1C1E), soft = f.dark ? rgb(0xFFFFFF, 0.62) : rgb(0x6C6C70)
        var y = text(ctx, f.title, font: display(104 * k, 680), color: ink, top: 150 * k, width: W - 140 * k, canvas: size, lineHeight: 112 * k)
        y = text(ctx, f.sub, font: ui(46 * k, .medium), color: soft, top: y + 30 * k, width: W - 180 * k, canvas: size, lineHeight: 58 * k)

        // The phone: the screenshot in a dark outline, bleeding off the bottom edge.
        let shot = NSImage(contentsOf: shots.appendingPathComponent(f.shot + ".png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let screenW = W * 0.80, screenH = screenW * CGFloat(shot.height) / CGFloat(shot.width)
        let bezel = 22 * k, radius = screenW * 0.135
        let top = max(y + 80 * k, 520 * k)
        let screen = CGRect(x: (W - screenW) / 2, y: H - top - screenH, width: screenW, height: screenH)
        let body = screen.insetBy(dx: -bezel, dy: -bezel)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -30 * k), blur: 90 * k, color: rgb(0x000000, f.dark ? 0.6 : 0.22))
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
        ctx.setFillColor(rgb(0x1C1C1E)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 3 * k, dy: 3 * k), cornerWidth: radius + bezel - 3 * k, cornerHeight: radius + bezel - 3 * k, transform: nil))
        ctx.setStrokeColor(rgb(0x5A5A5F)); ctx.setLineWidth(3 * k); ctx.strokePath()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(shot, in: screen)
        ctx.restoreGState()

        let url = dir.appendingPathComponent(f.file + ".png")
        try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
    }
}
print("ok")
