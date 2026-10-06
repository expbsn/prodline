import SwiftUI
import UIKit
import CoreText

extension EnvironmentValues {
    @Entry var accent: Accent = .neutral
}

// MARK: - Haptics

enum Haptics {
    private static var on: Bool { AppSettings.haptics }
    static func tap() { if on { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.75) } }
    static func soft() { if on { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
    static func heavy() { if on { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func warning() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
}
