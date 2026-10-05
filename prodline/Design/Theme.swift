import SwiftUI
import UIKit
import CoreText

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// 0xRRGGBB of a resolved color.
    var hex: Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return c(r) << 16 | c(g) << 8 | c(b)
    }
}

/// The app chrome is neutral; color comes from projects.
enum Theme {
    static let ink = Color(hex: 0x1C1C1E)
    static let inkSoft = Color(hex: 0x3A3A3C)
    static let secondary = Color(hex: 0x8E8E93)
    static let tertiary = Color(hex: 0xC7C7CC)
    static let line = Color(hex: 0xE5E5EA)
    static let background = Color(hex: 0xF2F2F5)
    static let card = Color.white

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

    var base: Color { Color(hex: hex) }

    /// Darker shade for the 3D edge of buttons.
    var dark: Color {
        let ui = UIColor(base)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if b < 0.25 { return .black }
        return Color(hue: h, saturation: min(s * 1.05, 1), brightness: b * 0.78)
    }

    var tint: Color { base.opacity(0.14) }
    var soft: Color { base.opacity(0.07) }

    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(Double((hex >> 16) & 0xFF) / 255)
        let g = lin(Double((hex >> 8) & 0xFF) / 255)
        let b = lin(Double(hex & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Readable foreground on top of `base`.
    var on: Color { luminance > 0.55 ? Theme.ink : .white }

    /// Text-safe version of the accent on light backgrounds (yellow gets darkened).
    var text: Color { luminance > 0.55 ? dark : base }
}

extension EnvironmentValues {
    @Entry var accent: Accent = .neutral
}

// MARK: - Typography

enum DisplayFont {
    private static var cache: [String: UIFont] = [:]

    /// Afacad Flux is a variable font; pick the weight via the `wght` axis.
    static func ui(_ size: CGFloat, weight: CGFloat) -> UIFont {
        let key = "\(size)-\(weight)"
        if let f = cache[key] { return f }
        let wght = 0x77676874 // 'wght'
        let desc = UIFontDescriptor(fontAttributes: [
            .name: "AfacadFlux-Regular",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ])
        let font = UIFont(descriptor: desc, size: size)
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

// MARK: - Haptics

enum Haptics {
    private static var on: Bool { AppSettings.haptics }
    static func tap() { if on { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.75) } }
    static func soft() { if on { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func warning() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
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

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    var dayMonth: String { formatted(.dateTime.month(.abbreviated).day()) }

    static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a.startOfDay, to: b.startOfDay).day ?? 0
    }
}
