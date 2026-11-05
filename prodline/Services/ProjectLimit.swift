import Foundation

/// Side projects die of too many side projects. Only so many can run at once (started or scheduled,
/// drafts don't count); everything else waits in the idea inbox or as a draft.
enum ProjectLimit {
    static let choices = [1, 2, 3, 0]

    /// Taking up a slot: running or about to start, and not closed by a pivot or kill.
    static func building(_ projects: [Project], now: Date = .now) -> [Project] {
        projects.filter { p in
            !p.isDraft && p.phase(on: now) != .finished && p.verdict != .pivot && p.verdict != .kill
        }
    }

    static func isFull(_ projects: [Project], profile: Profile, now: Date = .now) -> Bool {
        profile.buildLimit > 0 && building(projects, now: now).count >= profile.buildLimit
    }

    static func freeSlots(_ projects: [Project], profile: Profile, now: Date = .now) -> Int? {
        profile.buildLimit > 0 ? max(0, profile.buildLimit - building(projects, now: now).count) : nil
    }

    /// When the next slot opens: the earliest planned end among those taking one.
    static func nextFree(_ projects: [Project], now: Date = .now) -> Date? {
        building(projects, now: now).map { $0.planEnd(on: now) }.min()
    }

    static func label(_ limit: Int) -> String { limit == 0 ? "Off" : "\(limit)" }
}
