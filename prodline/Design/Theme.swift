import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import CoreText

extension EnvironmentValues {
    @Entry var accent: Accent = .neutral
    /// False for tabs kept alive in the background.
    @Entry var isActiveTab: Bool = true
}

extension View {
    /// Screens draw their own top bar; hide the system one (iOS only, the Mac has none in panes).
    func hiddenNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

// MARK: - Haptics

enum Haptics {
    private static var on: Bool { AppSettings.haptics }
    #if canImport(UIKit)
    static func tap() { if on { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.75) } }
    static func soft() { if on { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
    static func heavy() { if on { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func warning() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
    #else
    // Force Touch trackpads: a light tick where the iPhone would tap.
    private static func perform(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        if on { NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now) }
    }
    static func tap() { perform(.generic) }
    static func soft() { perform(.alignment) }
    static func heavy() { perform(.levelChange) }
    static func select() { perform(.alignment) }
    static func success() { perform(.levelChange) }
    static func warning() { perform(.generic) }
    #endif
}
