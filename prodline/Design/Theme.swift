import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    static let blue = Color(hex: 0x1CB0F6)
    static let blueDark = Color(hex: 0x1899D6)
    static let blueTint = Color(hex: 0xDDF4FF)
    static let green = Color(hex: 0x58CC02)
    static let greenDark = Color(hex: 0x58A700)
    static let greenTint = Color(hex: 0xD7FFB8)
    static let red = Color(hex: 0xFF4B4B)
    static let redDark = Color(hex: 0xEA2B2B)
    static let redTint = Color(hex: 0xFFDFE0)
    static let orange = Color(hex: 0xFF9600)
    static let orangeDark = Color(hex: 0xCC7900)
    static let orangeTint = Color(hex: 0xFFEBCC)
    static let yellow = Color(hex: 0xFFC800)
    static let purple = Color(hex: 0xCE82FF)
    static let purpleDark = Color(hex: 0xA568CC)

    static let ink = Color(hex: 0x4B4B4B)
    static let inkLight = Color(hex: 0xAFAFAF)
    static let line = Color(hex: 0xE5E5E5)
    static let surface = Color(hex: 0xF7F7F7)
    static let background = Color.white

    /// Colors a project can be tagged with.
    static let palette: [Color] = [blue, green, orange, purple, red, yellow]
}

extension Font {
    /// Pixel accent font for prominent text.
    static func display(_ size: CGFloat) -> Font {
        .custom("GeistPixel-Regular", size: size)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Formatting

extension Int {
    /// "2 weeks", "10 days"
    var durationText: String {
        if self % 7 == 0 {
            let w = self / 7
            return "\(w) week\(w == 1 ? "" : "s")"
        }
        return "\(self) day\(self == 1 ? "" : "s")"
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}

extension Date {
    static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a.startOfDay, to: b.startOfDay).day ?? 0
    }
}
