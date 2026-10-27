// Draws the demo projects' logos (the covers of the DEBUG demo and App Store screenshot sets).
// swiftc -O design/make_demo_logos.swift -o /tmp/logos && /tmp/logos design/demo-logos
// Then copy each PNG into prodline/Assets.xcassets/Cover-<name>.imageset.

import AppKit
import CoreGraphics

let N: CGFloat = 1024
func color(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func render(_ name: String, _ top: Int, _ bottom: Int, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(N), height: Int(N), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: N), end: CGPoint(x: N, y: 0), options: [])
    // y up; draw in a 0...N space
    draw(ctx)
    let out = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(name).png")
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: out)
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

// Habit Hero: a sprout, stem and two leaves.
render("habit-hero", 0x7BE23A, 0x3FA301) { c in
    c.setFillColor(color(0xFFFFFF))
    c.setStrokeColor(color(0xFFFFFF)); c.setLineWidth(46); c.setLineCap(.round)
    c.move(to: CGPoint(x: 512, y: 250)); c.addCurve(to: CGPoint(x: 512, y: 560), control1: CGPoint(x: 500, y: 360), control2: CGPoint(x: 524, y: 470)); c.strokePath()
    func leaf(_ tip: CGPoint, _ base: CGPoint, _ bend: CGFloat) {
        let p = CGMutablePath()
        let mid = CGPoint(x: (tip.x + base.x) / 2, y: (tip.y + base.y) / 2)
        let dx = tip.y - base.y, dy = -(tip.x - base.x)
        p.move(to: base)
        p.addQuadCurve(to: tip, control: CGPoint(x: mid.x + dx * bend, y: mid.y + dy * bend))
        p.addQuadCurve(to: base, control: CGPoint(x: mid.x - dx * bend, y: mid.y - dy * bend))
        c.addPath(p); c.fillPath()
    }
    leaf(CGPoint(x: 760, y: 760), CGPoint(x: 516, y: 540), 0.42)
    leaf(CGPoint(x: 290, y: 690), CGPoint(x: 508, y: 520), 0.42)
    c.setFillColor(color(0xFFFFFF, 0.35))
    c.addPath(rr(CGRect(x: 352, y: 200, width: 320, height: 64), 32)); c.fillPath()
}

// Pixel Quest: a pixel critter on an 8x8 grid.
render("pixel-quest", 0xB27BFF, 0x6A2BE0) { c in
    let rows = ["00100100", "00111100", "01111110", "11011011", "11111111", "00100100", "01011010", "10100101"]
    let cell: CGFloat = 70, ox = (N - cell * 8) / 2, oy = (N - cell * 8) / 2
    c.setFillColor(color(0xFFFFFF))
    for (r, row) in rows.enumerated() {
        for (i, ch) in row.enumerated() where ch == "1" {
            c.fill(CGRect(x: ox + CGFloat(i) * cell, y: oy + CGFloat(7 - r) * cell, width: cell - 6, height: cell - 6))
        }
    }
    c.setFillColor(color(0xFFD84D))
    for i in [2, 5] { c.fill(CGRect(x: ox + CGFloat(i) * cell, y: oy + 4 * cell, width: cell - 6, height: cell - 6)) }
}

// Side Shop: a price tag.
render("side-shop", 0x3A3A3C, 0x111113) { c in
    c.saveGState()
    c.translateBy(x: 512, y: 512); c.rotate(by: -.pi / 4)
    let tag = CGMutablePath()
    tag.move(to: CGPoint(x: -150, y: -260))
    tag.addLine(to: CGPoint(x: 150, y: -260))
    tag.addLine(to: CGPoint(x: 150, y: 170))
    tag.addLine(to: CGPoint(x: 0, y: 300))
    tag.addLine(to: CGPoint(x: -150, y: 170))
    tag.closeSubpath()
    c.setFillColor(color(0xF4EBDD))
    c.addPath(tag); c.fillPath()
    c.setBlendMode(.normal)
    c.setFillColor(color(0x1E1E20))
    c.fillEllipse(in: CGRect(x: -40, y: 130, width: 80, height: 80))
    c.setFillColor(color(0xE8553D))
    c.addPath(rr(CGRect(x: -95, y: -150, width: 190, height: 40), 20)); c.fillPath()
    c.setFillColor(color(0x1E1E20, 0.25))
    c.addPath(rr(CGRect(x: -95, y: -80, width: 130, height: 34), 17)); c.fillPath()
    c.restoreGState()
}

// Tiny Invoice: a document with lines, one highlighted.
render("tiny-invoice", 0x4F8CFF, 0x1F55E0) { c in
    let doc = CGMutablePath()
    let x: CGFloat = 322, y: CGFloat = 220, w: CGFloat = 380, h: CGFloat = 560, fold: CGFloat = 110
    doc.move(to: CGPoint(x: x, y: y))
    doc.addLine(to: CGPoint(x: x + w, y: y))
    doc.addLine(to: CGPoint(x: x + w, y: y + h - fold))
    doc.addLine(to: CGPoint(x: x + w - fold, y: y + h))
    doc.addLine(to: CGPoint(x: x, y: y + h))
    doc.closeSubpath()
    c.setFillColor(color(0xFFFFFF)); c.addPath(doc); c.fillPath()
    c.setFillColor(color(0xC9DAFF))
    let f = CGMutablePath(); f.move(to: CGPoint(x: x + w - fold, y: y + h)); f.addLine(to: CGPoint(x: x + w - fold, y: y + h - fold)); f.addLine(to: CGPoint(x: x + w, y: y + h - fold)); f.closeSubpath()
    c.addPath(f); c.fillPath()
    c.setFillColor(color(0x1F55E0, 0.3))
    for (i, lw) in [220.0, 280, 180].enumerated() { c.addPath(rr(CGRect(x: x + 50, y: y + h - 190 - CGFloat(i) * 70, width: CGFloat(lw), height: 30), 15)); c.fillPath() }
    c.setFillColor(color(0xFFC83D))
    c.addPath(rr(CGRect(x: x + 50, y: y + 60, width: 280, height: 64), 22)); c.fillPath()
}

// Moonlog: a crescent with two stars.
render("moonlog", 0x2B3170, 0x12153A) { c in
    c.saveGState()
    c.addRect(CGRect(x: 0, y: 0, width: N, height: N))
    c.addEllipse(in: CGRect(x: 420, y: 370, width: 430, height: 430))
    c.clip(using: .evenOdd)
    c.setFillColor(color(0xFFE08A))
    c.fillEllipse(in: CGRect(x: 232, y: 232, width: 540, height: 540))
    c.restoreGState()
    c.setFillColor(color(0xFFFFFF))
    func star(_ p: CGPoint, _ r: CGFloat) {
        let s = CGMutablePath()
        s.move(to: CGPoint(x: p.x, y: p.y + r)); s.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
        s.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p); s.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
        s.closeSubpath(); c.addPath(s); c.fillPath()
    }
    star(CGPoint(x: 700, y: 620), 50); star(CGPoint(x: 800, y: 500), 28)
}
// Flaky App (test project for a failing endpoint): a lightning bolt.
render("flaky-app", 0xF2A93B, 0xD9762F) { c in
    let b = CGMutablePath()
    b.move(to: CGPoint(x: 560, y: 820)); b.addLine(to: CGPoint(x: 330, y: 470)); b.addLine(to: CGPoint(x: 500, y: 470))
    b.addLine(to: CGPoint(x: 450, y: 200)); b.addLine(to: CGPoint(x: 700, y: 570)); b.addLine(to: CGPoint(x: 530, y: 570)); b.closeSubpath()
    c.setFillColor(color(0xFFFFFF)); c.addPath(b); c.fillPath()
}
print("ok")
