// Renders the Prodline mark: a "p" whose crossbar and stem run out as dashed production lines.
// swift design/make_logo.swift  →  PNG app icons + SVG
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let stroke: CGFloat = 100

struct Seg { let from: CGPoint; let to: CGPoint }

// Geometry on a 1024 canvas (y down). Mirrored in prodline/Design/LogoMark.swift; keep both in sync.
let stemX: CGFloat = 490
let stemTop: CGFloat = 390
let barY: CGFloat = 490
// Stem up from the bottom, round over to the right and back down to the crossbar.
func bowl() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: stemX, y: 630))
    p.addLine(to: CGPoint(x: stemX, y: stemTop))
    p.addCurve(to: CGPoint(x: 672, y: 190), control1: CGPoint(x: stemX, y: 250), control2: CGPoint(x: 552, y: 190))
    p.addCurve(to: CGPoint(x: 856, y: 342), control1: CGPoint(x: 792, y: 190), control2: CGPoint(x: 856, y: 262))
    p.addCurve(to: CGPoint(x: 700, y: barY), control1: CGPoint(x: 856, y: 430), control2: CGPoint(x: 792, y: barY))
    p.addLine(to: CGPoint(x: 402, y: barY))
    return p
}
// Crossbar breaks into a dash and a dot toward the left edge.
let left: [Seg] = [
    Seg(from: CGPoint(x: 266, y: barY), to: CGPoint(x: 242, y: barY)),
    Seg(from: CGPoint(x: 106, y: barY), to: CGPoint(x: 106, y: barY)),
]
// Stem breaks into a dash and a dot toward the bottom edge.
let down: [Seg] = [
    Seg(from: CGPoint(x: stemX, y: 766), to: CGPoint(x: stemX, y: 790)),
    Seg(from: CGPoint(x: stemX, y: 926), to: CGPoint(x: stemX, y: 926)),
]

func draw(in ctx: CGContext, bg: NSColor?, ink: NSColor) {
    if let bg { ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S)) }
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1) // y down
    ctx.setStrokeColor(ink.cgColor)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(bowl()); ctx.strokePath()
    for s in left + down { ctx.move(to: s.from); ctx.addLine(to: s.to); ctx.strokePath() }
}

func png(_ name: String, bg: NSColor?, ink: NSColor) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    draw(in: ctx, bg: bg, ink: ink)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}

func svg(_ name: String) {
    func pt(_ p: CGPoint) -> String { "\(Int(p.x)) \(Int(p.y))" }
    var d = ""
    bowl().applyWithBlock { el in
        let e = el.pointee
        switch e.type {
        case .moveToPoint: d += "M\(pt(e.points[0])) "
        case .addLineToPoint: d += "L\(pt(e.points[0])) "
        case .addCurveToPoint: d += "C\(pt(e.points[0])) \(pt(e.points[1])) \(pt(e.points[2])) "
        default: break
        }
    }
    for s in left + down { d += "M\(pt(s.from)) L\(pt(s.to)) " }
    let out = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
      <rect width="1024" height="1024" fill="#F2F2F5"/>
      <path d="\(d)" fill="none" stroke="#1C1C1E" stroke-width="\(Int(stroke))" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    """
    try! out.write(toFile: name, atomically: true, encoding: .utf8)
}

let ink = NSColor(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255, alpha: 1)
let paper = NSColor(red: 0xF2/255, green: 0xF2/255, blue: 0xF5/255, alpha: 1)
let night = NSColor(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255, alpha: 1)
png("AppIcon-light.png", bg: paper, ink: ink)
png("AppIcon-dark.png", bg: night, ink: NSColor(white: 0.96, alpha: 1))
png("AppIcon-tinted.png", bg: .black, ink: .white) // iOS tints the white mark
png("Mark.png", bg: nil, ink: ink)
svg("prodline-mark.svg")
print("done")
