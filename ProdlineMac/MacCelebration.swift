import SwiftUI

/// The Mac's side of the iPhone's CelebrationCenter (the engines call it the same way): one banner at a
/// time over the window, no full-screen moments.
@Observable
final class CelebrationCenter {
    struct Banner: Equatable { var title: String; var subtitle: String; var accent: Accent }
    struct ShipMoment: Equatable {
        let daysEarly: Int
        let plannedDays: Int
        let project: String
        let accent: Accent
        let xp: Int
    }
    enum Kind { case checkpoint, goals(Int), other }

    var banner: Banner?
    private var hide: Task<Void, Never>?

    func fire(title: String, subtitle: String, accent: Accent = .neutral, confetti: Bool = true, xp: Int = 0, kind: Kind = .other) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { banner = Banner(title: title, subtitle: subtitle, accent: accent) }
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { banner = nil }
        }
    }

    /// Today's first progress lights the streak.
    func lightStreak(_ days: Int) {
        fire(title: days == 1 ? "Streak started" : "\(days)-day streak", subtitle: "Today counts", accent: Accent(hex: 0xFF9600))
    }

    func celebrateShip(_ m: ShipMoment) {
        fire(title: "Shipped \(m.daysEarly) day\(m.daysEarly == 1 ? "" : "s") early! +\(m.xp) XP", subtitle: m.project, accent: m.accent)
    }
}

struct CelebrationBanner: View {
    let banner: CelebrationCenter.Banner
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(banner.accent.on)
                .frame(width: 30, height: 30).background(Circle().fill(banner.accent.base))
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title).font(.display(16, 750))
                Text(banner.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }
}
