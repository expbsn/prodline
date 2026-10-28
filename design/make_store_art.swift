// Composes the iPhone App Store screenshots, the header (21:9) and the search results asset (3:2) with SwiftUI.
// Screenshots: the real screens in a drawn iPhone 17 Pro, lit from the top left, on a gradient in each screen's
// color. Header and search: the hand-held mockup (design/mockup.png) on green, its screen swapped for the sharp shot.
// swiftc -O -parse-as-library design/make_store_art.swift -o /tmp/storeart && /tmp/storeart <shots dir> marketing/app-store [shots|header|search]
// Shots: the simulator with -PRODLINE_STORE YES (dash, traction, plan, picker, verdict, board.png). See marketing/app-store.md.
import AppKit
import CoreText
import SwiftUI

let args = CommandLine.arguments
let shotsDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])

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
        let out = warp(shot, f).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: big, kCIInputMaskImageKey: mask])
            .cropped(to: big.extent)
        let cg = ci.createCGImage(out, from: big.extent)!
        return NSImage(cgImage: cg, size: big.extent.size)
    }
}

/// The hand-held phone with a soft shadow, the way the light falls in the backdrop.
struct HeldPhone: View {
    let image: NSImage
    let tint: Color
    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: image.size.width, height: image.size.height)
            .shadow(color: tint.opacity(0.35), radius: image.size.width * 0.02, x: image.size.width * 0.012, y: image.size.width * 0.02)
    }
}

let green = 0x3FA300

/// A green take on the backdrop: deeper at the top right, a light haze toward the bottom left.
struct GreenBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let m = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [shade(green, -0.12), shade(green, 0.08)], startPoint: .bottomLeading, endPoint: .topTrailing)
                RadialGradient(colors: [shade(green, -0.7).opacity(0.75), shade(green, -0.7).opacity(0)],
                               center: .init(x: 0.05, y: 1.05), startRadius: 0, endRadius: m * 0.75)
                RadialGradient(colors: [.white.opacity(0.22), .white.opacity(0)], center: .init(x: 0.25, y: 0),
                               startRadius: 0, endRadius: m * 0.55)
            }
        }
    }
}

// MARK: Header

struct Header: View {
    let size = CGSize(width: 3840, height: 1646)
    var body: some View {
        // The mockup's bottom edge (the wrist) sits on the canvas's bottom edge.
        let f: CGFloat = 2.2
        let phone = HandPhone.image(screen: shotsDir.appendingPathComponent("dash.png"), scale: f)
        // Mockup point (683, 270) is the top middle of the phone; the arm runs off the bottom edge.
        let x = 2420 - 683 * f, y = 110 - 270 * f
        ZStack(alignment: .topLeading) {
            GreenBackdrop()
            VStack(alignment: .leading, spacing: 40) {
                Text("Finish what\nyou start.")
                    .font(display(210, 680)).foregroundStyle(.white).lineSpacing(-30)
                Text("Every side project on a short clock:\nbuild, launch, then decide.")
                    .font(.system(size: 68, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineSpacing(8)
            }
            .shadow(color: shade(green, 0.6).opacity(0.3), radius: 20, y: 8)
            .padding(.leading, 300).padding(.top, 380)
            HeldPhone(image: phone, tint: shade(green, 0.75))
                .position(x: x + phone.size.width / 2, y: y + phone.size.height / 2)
            Chip(symbol: "checkmark", tint: Color(hex: 0x46B500), title: "Habit list done", detail: "Habit Hero · from GitHub", s: 1.8)
                .rotationEffect(.degrees(-3))
                .position(x: 3260, y: 560)
            Chip(symbol: "flame.fill", tint: Color(hex: 0xFF8A00), title: "28 day streak", detail: "Keep it going", s: 1.8)
                .rotationEffect(.degrees(3))
                .position(x: 3330, y: 960)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: Search results

/// After the iOS search reference: a big line top left, a short one bottom left, the phone held up on the right.
struct Search: View {
    let size = CGSize(width: 3840, height: 2560)
    var body: some View {
        let f: CGFloat = 3.2
        let phone = HandPhone.image(screen: shotsDir.appendingPathComponent("dash.png"), scale: f)
        let x = 2780 - 683 * f, y = 170 - 270 * f
        ZStack(alignment: .topLeading) {
            GreenBackdrop()
            Text("Finish\nwhat you\nstart.")
                .font(display(330, 700)).foregroundStyle(.white).lineSpacing(-50)
                .shadow(color: shade(green, 0.6).opacity(0.3), radius: 24, y: 10)
                .padding(.leading, 230).padding(.top, 230)
            Text("Plan, ship and track every side\nproject. Live numbers from the\ntools you use, a clear verdict.")
                .font(.system(size: 96, weight: .medium)).foregroundStyle(.white.opacity(0.92)).lineSpacing(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 230).padding(.bottom, 230)
            HeldPhone(image: phone, tint: shade(green, 0.75))
                .position(x: x + phone.size.width / 2, y: y + phone.size.height / 2)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

@main
struct StoreArt {
    @MainActor static func main() {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "prodline/fonts/AfacadFlux-VariableFont_slnt,wght.ttf") as CFURL, .process, nil)
        let only = args.count > 3 ? args[3] : ""
        if only.isEmpty || only == "shots" {
            for (size, folder) in [(CGSize(width: 1206, height: 2622), "iphone-6.1"), (CGSize(width: 1320, height: 2868), "iphone-6.9")] {
                for s in shots { render(ScreenshotFrame(shot: s, size: size), size, to: "\(folder)/\(s.file).png") }
            }
        }
        if only.isEmpty || only == "header" { render(Header(), CGSize(width: 3840, height: 1646), to: "header-21x9.png") }
        if only.isEmpty || only == "search" { render(Search(), CGSize(width: 3840, height: 2560), to: "search-3x2.png") }
    }
}
