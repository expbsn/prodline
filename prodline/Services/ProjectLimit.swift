import Foundation

/// Side projects die of too many side projects. Only so many can be in the build phase at once;
/// everything else waits in the idea inbox.
enum ProjectLimit {
    static let choices = [1, 2, 3, 0]

    /// Taking up a build slot: building now or about to start, and not closed by a pivot or kill.
    static func building(_ projects: [Project], now: Date = .now) -> [Project] {
        projects.filter { p in
            let phase = p.phase(on: now)
            return (phase == .building || phase == .upcoming) && p.verdict != .pivot && p.verdict != .kill
        }
    }

    static func isFull(_ projects: [Project], profile: Profile, now: Date = .now) -> Bool {
        profile.buildLimit > 0 && building(projects, now: now).count >= profile.buildLimit
    }

    static func freeSlots(_ projects: [Project], profile: Profile, now: Date = .now) -> Int? {
        profile.buildLimit > 0 ? max(0, profile.buildLimit - building(projects, now: now).count) : nil
    }

    /// When the next slot opens: the earliest build phase among those taking one.
    static func nextFree(_ projects: [Project], now: Date = .now) -> Date? {
        building(projects, now: now).map(\.buildEnd).min()
    }

    static func label(_ limit: Int) -> String { limit == 0 ? "Off" : "\(limit)" }
}
