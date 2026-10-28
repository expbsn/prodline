// Composes the iPhone App Store screenshots, the header (21:9) and the search results asset (3:2) with SwiftUI.
// Screenshots: the real screens in a drawn iPhone 17 Pro, lit from the top left, on a gradient in each screen's
// color. Header: the five steps (create, plan, connect, track, decide) as pieces of the real screens on one dotted
// line. Search: the hand-held mockup (design/mockup.png) on green, its screen swapped for the sharp shot.
// swiftc -O -parse-as-library design/make_store_art.swift -o /tmp/storeart && /tmp/storeart <shots dir> <cards dir> marketing/app-store [shots|header|search]
// Shots: the simulator with -PRODLINE_STORE YES (dash, traction, plan, picker, verdict, board.png); cards: the Mac
// snapshot writer (card-<project>.png). See marketing/app-store.md.
import AppKit
import CoreText
import SwiftUI

let args = CommandLine.arguments
let shotsDir = URL(fileURLWithPath: args[1]), cardsDir = URL(fileURLWithPath: args[2]), outDir = URL(fileURLWithPath: args[3])

// MARK: Basics

extension Color {
    init(hex: Int, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
}

/// Mixes a hex color toward white (t < 0) or black (t > 0).
func shade(_ hex: Int, _ t: Double) -> Color {
    let c = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { Double($0) / 255 }
    let m = c.map { t < 0 ? $0 + (1 - $0) * -t : $0 * (1 - t) }
    return Color(.sRGB, red: m[0], green: m[1], blue: m[2])
}

func display(_ size: CGFloat, _ weight: CGFloat) -> Font {
    let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: "AfacadFlux-Regular",
                                                  kCTFontVariationAttribute: [0x77676874: weight]] as CFDictionary)
    return Font(CTFontCreateWithFontDescriptor(d, size, nil))
}

func image(_ url: URL) -> NSImage { NSImage(contentsOf: url)! }

@MainActor
func render<V: View>(_ view: V, _ size: CGSize, to name: String) {
    let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
    r.scale = 1
    let cg = r.cgImage!
    // App Store wants no alpha: flatten onto an opaque bitmap.
    let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    let url = outDir.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
    print(name)
}

// MARK: iPhone 17 Pro

/// The phone from the front: silver frame, black border, the screenshot, side buttons and a little glass glare.
/// `width` is the body's width; proportions follow the real device (71.9 x 150 mm, 6.3" screen).
struct Phone: View {
    let shot: NSImage
    let width: CGFloat
    var shadowTint: Color = .black

    var body: some View {
        let screenW = width / 1.08
        let border = (width - screenW) / 2
        let metal = border * 0.38
        let screenH = screenW * shot.size.height / shot.size.width
        let h = screenH + border * 2
        let screenR = screenW * 0.145
        let bodyR = screenR + border
        let shape = RoundedRectangle(cornerRadius: bodyR, style: .continuous)

        ZStack {
            // Buttons sit behind the body and stick out a little.
            buttons(h: h, metal: metal)
            shape.fill(LinearGradient(stops: [
                .init(color: Color(hex: 0xC9CBCF), location: 0),
                .init(color: Color(hex: 0xF4F5F7), location: 0.18),
                .init(color: Color(hex: 0xB4B6BA), location: 0.5),
                .init(color: Color(hex: 0xE9EAEC), location: 0.8),
                .init(color: Color(hex: 0x9EA0A5), location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            // Shadows: a tight contact one and a wide one cast down and to the right.
            .shadow(color: .black.opacity(0.22), radius: width * 0.012, x: width * 0.004, y: width * 0.01)
            .shadow(color: shadowTint.opacity(0.32), radius: width * 0.09, x: width * 0.05, y: width * 0.08)
            shape.strokeBorder(Color(hex: 0x7C7F85), lineWidth: max(1.5, width * 0.0025))
            shape.inset(by: metal * 0.35).strokeBorder(.white.opacity(0.7), lineWidth: max(1, width * 0.0016))
            RoundedRectangle(cornerRadius: bodyR - metal, style: .continuous)
                .fill(Color(hex: 0x050506))
                .padding(metal)
            Image(nsImage: shot).resizable().interpolation(.high)
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: screenR, style: .continuous))
            // Glass: a soft diagonal sheen from the top left.
            RoundedRectangle(cornerRadius: bodyR - metal, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.13), location: 0),
                                             .init(color: .white.opacity(0.03), location: 0.35),
                                             .init(color: .white.opacity(0), location: 0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(metal)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: h)
    }

    private func buttons(h: CGFloat, metal: CGFloat) -> some View {
        let out = metal * 0.75, thick = metal * 1.6
        let button = { (from: CGFloat, to: CGFloat, left: Bool) -> AnyView in
            AnyView(RoundedRectangle(cornerRadius: thick / 2, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x9EA0A5), Color(hex: 0xE4E5E8), Color(hex: 0xA6A8AD)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: thick, height: h * (to - from))
                .position(x: left ? -out + thick / 2 : width + out - thick / 2, y: h * (from + to) / 2))
        }
        return ZStack {
            button(0.165, 0.205, true)   // Action button
            button(0.245, 0.31, true)    // Volume up
            button(0.33, 0.395, true)    // Volume down
            button(0.27, 0.365, false)   // Side button
            button(0.525, 0.575, false)  // Camera Control
        }
        .frame(width: width, height: h)
    }
}

// MARK: Floating bits

/// A small app-style card: a tinted symbol, a title and a detail line.
struct Chip: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let s: CGFloat

    var body: some View {
        HStack(spacing: 16 * s) {
            Image(systemName: symbol)
                .font(.system(size: 22 * s, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54 * s, height: 54 * s)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 3 * s) {
                Text(title).font(.system(size: 25 * s, weight: .semibold)).foregroundStyle(Color(hex: 0x1C1C1E))
                Text(detail).font(.system(size: 20 * s, weight: .medium)).foregroundStyle(Color(hex: 0x6C6C70))
            }
            .fixedSize()
        }
        .padding(.leading, 16 * s).padding(.trailing, 30 * s).padding(.vertical, 16 * s)
        .background(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).fill(.white))
        .shadow(color: .black.opacity(0.12), radius: 4 * s, y: 2 * s)
        .shadow(color: .black.opacity(0.22), radius: 34 * s, x: 8 * s, y: 26 * s)
    }
}

/// The background: a gradient in the screen's color, lit from the top left, a touch darker toward the bottom right.
struct Backdrop: View {
    let hex: Int
    var light: Double = -0.78
    var deep: Double = -0.12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [shade(hex, light), shade(hex, (light + deep) / 2), shade(hex, deep)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)], center: .init(x: 0.1, y: 0.05),
                               startRadius: 0, endRadius: max(w, h) * 0.7)
                RadialGradient(colors: [shade(hex, 0.35).opacity(0.35), .clear], center: .init(x: 1, y: 1),
                               startRadius: 0, endRadius: max(w, h) * 0.6)
                // A light beam falling across the scene.
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.35, height: h * 2.2)
                    .rotationEffect(.degrees(28))
                    .offset(x: -w * 0.12)
                    .blur(radius: w * 0.04)
            }
        }
    }
}

// MARK: iPhone screenshots

struct Shot { let file, shot, title, sub: String; let hex: Int }

let shots = [
    Shot(file: "01-dash", shot: "dash", title: "Finish what\nyou start.", sub: "Every side project on a short clock.", hex: 0x46B500),
    Shot(file: "02-numbers", shot: "traction", title: "Numbers that\ncome in on their own.", sub: "Revenue and visitors, live from Stripe.", hex: 0x2F6BFF),
    Shot(file: "03-plan", shot: "plan", title: "A deadline for\nevery step.", sub: "Checkpoints, goals and a streak.", hex: 0xF29A16),
    Shot(file: "04-services", shot: "picker", title: "25+ services,\nconnected.", sub: "Your keys stay in your Keychain.", hex: 0x635BFF),
    Shot(file: "05-decide", shot: "verdict", title: "Keep, pivot\nor kill.", sub: "Decide on numbers, not on a feeling.", hex: 0x8A45F5),
    Shot(file: "06-widgets", shot: "board", title: "Always\nin sight.", sub: "Your next deadline on the Home Screen.", hex: 0x14A38B),
]

struct ScreenshotFrame: View {
    let shot: Shot
    let size: CGSize

    var body: some View {
        let k = size.width / 1206
        let ink = shade(shot.hex, 0.72)
        ZStack(alignment: .top) {
            Backdrop(hex: shot.hex)
            VStack(spacing: 0) {
                Text(shot.title)
                    .font(display(112 * k, 660)).foregroundStyle(ink)
                    .multilineTextAlignment(.center).lineSpacing(-14 * k)
                    .padding(.top, 130 * k)
                Text(shot.sub)
                    .font(.system(size: 42 * k, weight: .medium)).foregroundStyle(ink.opacity(0.68))
                    .padding(.top, 26 * k)
                Spacer(minLength: 0)
                Phone(shot: image(shotsDir.appendingPathComponent(shot.shot + ".png")), width: size.width * 0.79,
                      shadowTint: shade(shot.hex, 0.75))
                    .padding(.bottom, 92 * k)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: Hand-held phone (design/mockup.png)

/// The hand-held mockup, upscaled, with the screen swapped for the sharp screenshot. The mockup is 1600 x 1200 with
/// the Dash screen already in it; its screen corners are measured below. Wherever the mockup's screen differs from
/// the screenshot (the fingers over the edge), the mockup stays on top.
enum HandPhone {
    static let mockup = URL(fileURLWithPath: "design/mockup.png")
    /// Screen corners in mockup pixels, y down: top left, top right, bottom left, bottom right.
    static let quad: [CGPoint] = [.init(x: 552, y: 283.5), .init(x: 810, y: 283.5), .init(x: 555, y: 844), .init(x: 816, y: 844)]

    static func image(screen: URL, scale f: CGFloat) -> NSImage {
        let mock = CIImage(contentsOf: mockup)!
        let shot = CIImage(contentsOf: screen)!
        let h = mock.extent.height
        let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

        /// The screenshot (or any image of its size) scaled down to the screen width, then put onto the quad.
        func warp(_ img: CIImage, _ f: CGFloat) -> CIImage {
            let w = (quad[1].x - quad[0].x) * f
            let small = img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: w / img.extent.width, kCIInputAspectRatioKey: 1])
            let pt = { (p: CGPoint) in CIVector(x: p.x * f, y: (h - p.y) * f) }
            return small.applyingFilter("CIPerspectiveTransform", parameters: [
                "inputTopLeft": pt(quad[0]), "inputTopRight": pt(quad[1]), "inputBottomLeft": pt(quad[2]), "inputBottomRight": pt(quad[3])])
        }
        /// White rounded rectangle the size of the screenshot: the screen's shape.
        let shape: CIImage = {
            let size = shot.extent.size
            let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(.black); ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(.white)
            ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8), cornerWidth: 140, cornerHeight: 140, transform: nil))
            ctx.fillPath()
            return CIImage(cgImage: ctx.makeImage()!)
        }()

        // Fingers: where the mockup's screen doesn't match the screenshot. The opening is wider than any text stroke,
        // so only finger-sized blobs survive.
        let diff = warp(shot, 1).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: mock])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.34, y: 0.33, z: 0.33, w: 0), "inputGVector": CIVector(x: 0.34, y: 0.33, z: 0.33, w: 0),
                "inputBVector": CIVector(x: 0.34, y: 0.33, z: 0.33, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.16])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 5])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 9])
            .cropped(to: mock.extent)
        let keep = warp(shape, 1).cropped(to: mock.extent)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: diff.applyingFilter("CIColorInvert")])
        let mask = keep.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: f, kCIInputAspectRatioKey: 1])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: f * 0.4])

        let big = mock.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: f, kCIInputAspectRatioKey: 1])
            .applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: f * 1.2, kCIInputIntensityKey: 0.6])
        let out = warp(shot, f).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: big, kCIInputMaskImageKey: mask])
            .cropped(to: big.extent)
        let cg = ci.createCGImage(out, from: big.extent)!
        return NSImage(cgImage: cg, size: big.extent.size)
    }
}

// MARK: Header: the five steps

/// A piece of a screenshot, in screenshot pixels.
func crop(_ shot: String, _ r: CGRect) -> NSImage {
    let cg = image(shotsDir.appendingPathComponent(shot + ".png")).cgImage(forProposedRect: nil, context: nil, hints: nil)!.cropping(to: r)!
    return NSImage(cgImage: cg, size: r.size)
}

/// One step: a numbered label above a piece of the app, floating on its own shadow.
struct StepPanel<Content: View>: View {
    let number: Int
    let verb: String
    let symbol: String
    let hex: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 34) {
            HStack(spacing: 18) {
                Text("\(number)")
                    .font(display(46, 760)).foregroundStyle(Color(hex: hex))
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(.white))
                Image(systemName: symbol).font(.system(size: 40, weight: .bold))
                Text(verb).font(display(64, 680))
            }
            .foregroundStyle(.white)
            .padding(.leading, 16).padding(.trailing, 44).padding(.vertical, 14)
            .background(Capsule().fill(Color(hex: hex)))
            .shadow(color: shade(hex, 0.4).opacity(0.45), radius: 22, y: 12)
            content()
        }
    }
}

/// A screen piece as a floating panel: rounded, with a tight contact shadow and a wide soft one.
struct Panel: View {
    let image: NSImage
    let width: CGFloat
    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: width, height: width * image.size.height / image.size.width)
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).strokeBorder(.white, lineWidth: 5))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 3)
            .shadow(color: .black.opacity(0.20), radius: 60, x: 14, y: 46)
    }
}

/// The logo's dot, dash and line, drawn as one long path that ties the steps together.
struct DotLine: View {
    let points: [CGPoint]
    var body: some View {
        Path { p in
            p.move(to: points[0])
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                p.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
            }
        }
        .stroke(Color(hex: 0x1C1C1E).opacity(0.18), style: StrokeStyle(lineWidth: 18, lineCap: .round, dash: [0, 40, 46, 40]))
    }
}

struct Header: View {
    let size = CGSize(width: 3840, height: 1646)
    var body: some View {
        let w: CGFloat = 640
        let xs: [CGFloat] = [-2, -1, 0, 1, 2].map { 1920 + $0 * 735 }
        let steps = [0x46B500, 0xF29A16, 0x635BFF, 0x2F6BFF, 0x8A45F5]
        ZStack {
            Color(hex: 0xF4F4F7)
            // A soft glow in each step's color.
            ForEach(0..<5, id: \.self) { i in
                RadialGradient(colors: [Color(hex: steps[i], 0.26), Color(hex: steps[i], 0)], center: .center, startRadius: 0, endRadius: 620)
                    .frame(width: 1240, height: 1240)
                    .position(x: xs[i], y: i.isMultiple(of: 2) ? 880 : 780)
            }
            DotLine(points: [CGPoint(x: -80, y: 1000), CGPoint(x: xs[0], y: 940), CGPoint(x: xs[1], y: 760), CGPoint(x: xs[2], y: 940),
                             CGPoint(x: xs[3], y: 760), CGPoint(x: xs[4], y: 940), CGPoint(x: 3920, y: 860)])

            StepPanel(number: 1, verb: "Create", symbol: "plus", hex: steps[0]) {
                ZStack {
                    Image(nsImage: image(cardsDir.appendingPathComponent("card-tiny-invoice.png"))).resizable().interpolation(.high)
                        .frame(width: 430, height: 602)
                        .shadow(color: .black.opacity(0.22), radius: 40, x: 10, y: 30)
                        .rotationEffect(.degrees(-9)).offset(x: -95, y: 14)
                    Image(nsImage: image(cardsDir.appendingPathComponent("card-habit-hero.png"))).resizable().interpolation(.high)
                        .frame(width: 450, height: 630)
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                        .shadow(color: .black.opacity(0.26), radius: 50, x: 14, y: 40)
                        .rotationEffect(.degrees(5)).offset(x: 110)
                }
                .frame(width: w, height: 700)
            }
            .position(x: xs[0], y: 850)
            StepPanel(number: 2, verb: "Plan", symbol: "calendar", hex: steps[1]) {
                Panel(image: crop("plan", CGRect(x: 48, y: 450, width: 1113, height: 1300)), width: w)
            }
            .position(x: xs[1], y: 790)
            StepPanel(number: 3, verb: "Connect", symbol: "link", hex: steps[2]) {
                Panel(image: crop("picker", CGRect(x: 48, y: 1100, width: 1098, height: 1265)), width: w)
            }
            .position(x: xs[2], y: 860)
            StepPanel(number: 4, verb: "Track", symbol: "chart.line.uptrend.xyaxis", hex: steps[3]) {
                Panel(image: crop("traction", CGRect(x: 53, y: 1135, width: 1098, height: 1164)), width: w)
            }
            .position(x: xs[3], y: 780)
            StepPanel(number: 5, verb: "Decide", symbol: "arrow.triangle.branch", hex: steps[4]) {
                Panel(image: crop("verdict", CGRect(x: 52, y: 442, width: 1083, height: 1366)), width: w)
            }
            .position(x: xs[4], y: 860)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: Search results

/// After Apple's search example: a muted sky-style gradient (deeper on top, a light haze at the bottom), a bold line
/// top left, a dark short line bottom left, the phone held up on the right.
struct Search: View {
    let size = CGSize(width: 3840, height: 2560)
    var body: some View {
        let W = size.width, H = size.height
        // Phone 78% of the height, its top 8% down, centered at 74% across.
        let f: CGFloat = 0.78 * H / 560
        let phone = HandPhone.image(screen: shotsDir.appendingPathComponent("dash.png"), scale: f)
        let x = 0.74 * W - 683 * f, y = 0.08 * H - 283 * f
        let hue = 0.285
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [
                .init(color: Color(hue: hue, saturation: 0.58, brightness: 0.70), location: 0),
                .init(color: Color(hue: hue, saturation: 0.46, brightness: 0.80), location: 0.45),
                .init(color: Color(hue: hue, saturation: 0.22, brightness: 0.92), location: 0.8),
                .init(color: Color(hue: hue, saturation: 0.10, brightness: 0.97), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // Haze low on the left, a little light from the top right.
            RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)], center: .init(x: 0.18, y: 1.05), startRadius: 0, endRadius: W * 0.45)
            RadialGradient(colors: [.white.opacity(0.18), .white.opacity(0)], center: .init(x: 0.8, y: 0), startRadius: 0, endRadius: W * 0.4)
            Text("FINISH\nWHAT YOU\nSTART.")
                .font(display(268, 720)).foregroundStyle(.white).lineSpacing(-46)
                .padding(.leading, 0.06 * W).padding(.top, 0.09 * H)
            Text("Plan it, ship it and watch the real\nnumbers come in. Then decide:\nkeep, pivot or kill.")
                .font(.system(size: 100, weight: .regular)).foregroundStyle(Color(hue: hue, saturation: 0.8, brightness: 0.24))
                .lineSpacing(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 0.06 * W).padding(.bottom, 0.1 * H)
            Image(nsImage: phone).resizable().interpolation(.high)
                .frame(width: phone.size.width, height: phone.size.height)
                .shadow(color: Color(hue: hue, saturation: 0.7, brightness: 0.25).opacity(0.25), radius: 40, x: 18, y: 30)
                .position(x: x + phone.size.width / 2, y: y + phone.size.height / 2)
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

@main
struct StoreArt {
    @MainActor static func main() {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "prodline/fonts/AfacadFlux-VariableFont_slnt,wght.ttf") as CFURL, .process, nil)
        let only = args.count > 4 ? args[4] : ""
        if only.isEmpty || only == "shots" {
            for (size, folder) in [(CGSize(width: 1206, height: 2622), "iphone-6.1"), (CGSize(width: 1320, height: 2868), "iphone-6.9")] {
                for s in shots { render(ScreenshotFrame(shot: s, size: size), size, to: "\(folder)/\(s.file).png") }
            }
        }
        if only.isEmpty || only == "header" { render(Header(), CGSize(width: 3840, height: 1646), to: "header-21x9.png") }
        if only.isEmpty || only == "search" { render(Search(), CGSize(width: 3840, height: 2560), to: "search-3x2.png") }
    }
}
