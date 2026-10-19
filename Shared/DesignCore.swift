import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#else
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

// Design primitives shared by the app, the widget extension and the Mac app (all compile this file).

extension PlatformColor {
    /// One color in light appearance, another in dark.
    static func dynamic(_ pick: @escaping (_ dark: Bool) -> PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
        UIColor { pick($0.userInterfaceStyle == .dark) }
        #else
        NSColor(name: nil) { pick($0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
        #endif
    }
}

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// One color in light mode, another in dark mode.
    init(light: Int, dark: Int) {
        self.init(PlatformColor.dynamic { $0 ? PlatformColor(hex: dark) : PlatformColor(hex: light) })
    }

    /// 0xRRGGBB of a resolved color.
    var hex: Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        (NSColor(self).usingColorSpace(.sRGB) ?? .black).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return c(r) << 16 | c(g) << 8 | c(b)
    }
}

extension PlatformColor {
    /// Hue, saturation, brightness and alpha (the Mac needs an RGB color space for these).
    var hsba: (h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #else
        (usingColorSpace(.sRGB) ?? .black).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #endif
        return (h, s, b, a)
    }

    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        (usingColorSpace(.sRGB) ?? .black).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }

    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The app chrome is neutral; color comes from projects. Every chrome color has a light and a dark value.
enum Theme {
    static let ink = Color(light: 0x1C1C1E, dark: 0xF5F5F7)
    static let inkSoft = Color(light: 0x3A3A3C, dark: 0xD1D1D6)
    static let secondary = Color(light: 0x8E8E93, dark: 0x98989F)
    static let tertiary = Color(light: 0xC7C7CC, dark: 0x5A5A5F)
    static let line = Color(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let background = Color(light: 0xF2F2F5, dark: 0x000000)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Text and icons on an `ink` fill (selected chips, the dark tile): white in light mode, near-black in dark.
    static let inverse = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// The thin highlight around project cards: bright on light, barely there on dark.
    static let rim = Color(PlatformColor.dynamic { PlatformColor(white: 1, alpha: $0 ? 0.14 : 0.7) })
    /// Small tiles set into a card: a shade darker than the card in light mode, a shade lighter in dark.
    static let inset = Color(light: 0xF2F2F5, dark: 0x2C2C2E)
    /// Switches when on: ink in light mode; in dark mode the white knob needs a colored track.
    static let switchOn = Color(light: 0x1C1C1E, dark: 0x34C759)
    /// Dark text that stays dark in both modes, for bright fills like yellow.
    static let inkFixed = Color(hex: 0x1C1C1E)

    static let flame = Color(hex: 0xFF9600)
    static let success = Color(hex: 0x34C759)
    static let danger = Color(hex: 0xFF3B30)

    /// Accent choices when a project has no cover photo.
    static let swatches: [Int] = [
        0x58CC02, 0x00B894, 0x1CB0F6, 0x5B5BF0, 0xA35CFF,
        0xFF5FA2, 0xFF4B4B, 0xFF9600, 0xFFC800, 0x3C3C43,
    ]
}

/// A project's color system, derived from one base color.
struct Accent: Equatable, Hashable {
    let hex: Int

    static let neutral = Accent(hex: 0x1C1C1E)
    /// Money moments (sales, revenue) are always gold, whatever the project color.
    static let sale = Accent(hex: 0xFFC800)

    /// Near-black accents (the neutral one, the graphite swatch) would vanish on a dark background,
    /// so in dark mode they turn a soft grey, with dark text on top.
    var isNearBlack: Bool { luminance < 0.06 }

    /// The app's own neutral (chips, buttons on Me…) rather than a project color: near-white in dark mode.
    var isNeutral: Bool { hex == 0x1C1C1E }

    var base: Color {
        if isNeutral { return Color(light: hex, dark: 0xF5F5F7) }
        return isNearBlack ? Color(light: hex, dark: 0xAEAEB2) : Color(hex: hex)
    }

    /// Darker shade for the 3D edge of buttons.
    var dark: Color {
        if isNeutral { return Color(light: 0x000000, dark: 0xAEAEB2) }
        if isNearBlack { return Color(light: 0x000000, dark: 0x7C7C80) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(hex: hex).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #else
        (NSColor(hex: hex).usingColorSpace(.sRGB) ?? .black).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #endif
        if b < 0.25 { return .black }
        return Color(hue: h, saturation: min(s * 1.05, 1), brightness: b * 0.78)
    }

    /// Washes of the accent; a little stronger in dark mode, where the light-mode amounts all but vanish.
    var tint: Color { wash(light: 0.14, dark: 0.24) }
    var soft: Color { wash(light: 0.07, dark: 0.12) }

    private func wash(light: CGFloat, dark: CGFloat) -> Color {
        let darkHex = isNeutral ? 0xF5F5F7 : isNearBlack ? 0xAEAEB2 : hex
        return Color(PlatformColor.dynamic { $0
            ? PlatformColor(hex: darkHex).withAlphaComponent(dark) : PlatformColor(hex: hex).withAlphaComponent(light) })
    }

    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(Double((hex >> 16) & 0xFF) / 255)
        let g = lin(Double((hex >> 8) & 0xFF) / 255)
        let b = lin(Double(hex & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Readable foreground on top of `base`.
    var on: Color { luminance > 0.55 ? Theme.inkFixed : isNearBlack ? Theme.inverse : .white }

    /// Text-safe version of the accent on the page (yellow gets darkened; near-black follows the text color).
    var text: Color { luminance > 0.55 ? dark : isNearBlack ? Theme.ink : base }
}

// MARK: - Typography

enum DisplayFont {
    private static var cache: [String: PlatformFont] = [:]

    /// Afacad Flux is a variable font; pick the weight via the `wght` axis.
    static func ui(_ size: CGFloat, weight: CGFloat) -> PlatformFont {
        let key = "\(size)-\(weight)"
        if let f = cache[key] { return f }
        let wght = 0x77676874 // 'wght'
        #if canImport(UIKit)
        let desc = UIFontDescriptor(fontAttributes: [
            .name: "AfacadFlux-Regular",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ])
        let font = UIFont(descriptor: desc, size: size)
        #else
        let desc = NSFontDescriptor(fontAttributes: [
            .name: "AfacadFlux-Regular",
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ])
        let font = NSFont(descriptor: desc, size: size) ?? .systemFont(ofSize: size, weight: .bold)
        #endif
        cache[key] = font
        return font
    }
}

extension Font {
    /// Accent font for prominent text.
    static func display(_ size: CGFloat, _ weight: CGFloat = 700) -> Font {
        Font(DisplayFont.ui(size, weight: weight))
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Accent font for prominent text. The bundled font's vertical metrics are tightened
    /// (tools/tighten_font_metrics.py) so wrapped lines and single lines both sit balanced.
    func display(_ size: CGFloat, _ weight: CGFloat = 700) -> some View {
        self.font(.display(size, weight))
    }
}

extension Text {
    /// Small tracked uppercase label ("MINIGAMES" style).
    func eyebrow(_ color: Color = Theme.secondary, size: CGFloat = 12) -> some View {
        self.font(.ui(size, .semibold))
            .tracking(size * 0.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Formatting

extension Int {
    /// "2 weeks", "10 days"
    var durationText: String {
        if self % 7 == 0 && self > 0 {
            let w = self / 7
            return "\(w) week\(w == 1 ? "" : "s")"
        }
        return "\(self) day\(self == 1 ? "" : "s")"
    }

    /// "2w", "10d"
    var shortDuration: String { self % 7 == 0 && self > 0 ? "\(self / 7)w" : "\(self)d" }
}

nonisolated extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    var dayMonth: String { formatted(.dateTime.month(.abbreviated).day()) }

    static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a.startOfDay, to: b.startOfDay).day ?? 0
    }
}

nonisolated extension Collection {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum Phase: String {
    case upcoming, building, observing, finished

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .building: "Building"
        case .observing: "Observing"
        case .finished: "Finished"
        }
    }

    var symbol: String {
        switch self {
        case .upcoming: "hourglass"
        case .building: "hammer.fill"
        case .observing: "chart.line.uptrend.xyaxis"
        case .finished: "flag.checkered"
        }
    }
}
