import Foundation
import UIKit

/// What the widgets know about the user's projects. The app writes it to the App Group container
/// after every refresh; the widget extension only reads it. Times stay absolute so the widget can
/// recompute "in 2 days" and the current phase as the clock moves on.
nonisolated struct WidgetData: Codable, Equatable, Sendable {
    var generatedAt: Date
    var streak: Int
    var projects: [WidgetProject]

    /// The project a widget shows when the user hasn't picked one: the nearest open deadline.
    func mostUrgent(on date: Date) -> WidgetProject? {
        projects
            .filter { $0.phase(on: date) != .finished }
            .min { a, b in (a.next(on: date)?.due ?? .distantFuture) < (b.next(on: date)?.due ?? .distantFuture) }
            ?? projects.first
    }

    func project(id: String?) -> WidgetProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }
}

nonisolated struct WidgetProject: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var accentHex: Int
    var startDate: Date
    var buildEnd: Date
    var observeEnd: Date
    var checkpoints: [WidgetCheckpoint]
    var metrics: [WidgetMetric]

    var initial: String { name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }
    var accent: Accent { Accent(hex: accentHex) }
    var url: URL { URL(string: "prodline://project/\(id)")! }

    func phase(on date: Date) -> Phase {
        let d = date.startOfDay
        if d < startDate { return .upcoming }
        if d < buildEnd { return .building }
        if d < observeEnd { return .observing }
        return .finished
    }

    /// Day within the current phase (1-based) and that phase's length.
    func phaseDay(on date: Date) -> (day: Int, of: Int) {
        switch phase(on: date) {
        case .upcoming: (0, max(1, Date.days(from: startDate, to: buildEnd)))
        case .building: (Date.days(from: startDate, to: date) + 1, max(1, Date.days(from: startDate, to: buildEnd)))
        case .observing: (Date.days(from: buildEnd, to: date) + 1, max(1, Date.days(from: buildEnd, to: observeEnd)))
        case .finished: (1, 1)
        }
    }

    func phaseProgress(on date: Date) -> Double {
        let (d, of) = phaseDay(on: date)
        return min(1, max(0, Double(d) / Double(of)))
    }

    func next(on date: Date) -> WidgetCheckpoint? { checkpoints.first { !$0.done } }
    var doneCount: Int { checkpoints.filter(\.done).count }
    func metric(_ key: String) -> WidgetMetric? { metrics.first { $0.key == key } }
}

nonisolated struct WidgetCheckpoint: Codable, Equatable, Sendable {
    var title: String
    var due: Date
    var done: Bool
    var isLaunch: Bool
    var goals: [WidgetGoal]
    var goalCount: Int
    var goalsDone: Int

    var progress: Double { goalCount == 0 ? 0 : Double(goalsDone) / Double(goalCount) }

    /// "Today", "Tomorrow", "In 3 days", "2 days late".
    func dueText(from date: Date) -> String {
        let n = Date.days(from: date, to: due)
        switch n {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...: return "In \(n) days"
        case -1: return "1 day late"
        default: return "\(-n) days late"
        }
    }
}

nonisolated struct WidgetGoal: Codable, Equatable, Sendable {
    var title: String
    var done: Bool
}

nonisolated struct WidgetMetric: Codable, Equatable, Sendable {
    var key: String
    var title: String
    var symbol: String
    var value: Double
    var formatted: String
    /// Change over the last 7 days, preformatted ("+1.2K"), nil without history.
    var delta: String?
    var deltaPositive: Bool
    /// Daily values, oldest first, ending today.
    var spark: [Double]
}

/// The App Group container both processes can see.
nonisolated enum SharedStore {
    static let groupID = "group.expbsn.app.prodline"
    static let widgetKinds = ["ProjectWidget", "TractionWidget", "LineupWidget"]

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
    private static var dataURL: URL? { container?.appendingPathComponent("widget.json") }
    private static var coversURL: URL? { container?.appendingPathComponent("covers", isDirectory: true) }

    static func read() -> WidgetData? {
        guard let url = dataURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetData.self, from: data)
    }

    /// Returns false when nothing changed, so the caller can skip reloading timelines.
    @discardableResult
    static func write(_ widgetData: WidgetData) -> Bool {
        guard let url = dataURL else { return false }
        if var old = read() {
            old.generatedAt = widgetData.generatedAt
            if old == widgetData { return false }
        }
        guard let data = try? encoder.encode(widgetData) else { return false }
        try? data.write(to: url, options: .atomic)
        return true
    }

    static func coverURL(_ id: String) -> URL? { coversURL?.appendingPathComponent("\(id).jpg") }

    static func cover(_ id: String) -> UIImage? {
        guard let url = coverURL(id) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Writes small covers and removes ones for projects that no longer exist. True if any changed.
    @discardableResult
    static func writeCovers(_ covers: [String: Data]) -> Bool {
        guard let dir = coversURL else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var changed = false
        for (id, data) in covers {
            guard let url = coverURL(id) else { continue }
            if (try? Data(contentsOf: url)) != data {
                try? data.write(to: url, options: .atomic)
                changed = true
            }
        }
        let keep = Set(covers.keys.map { "\($0).jpg" })
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            changed = true
        }
        return changed
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = .sortedKeys
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

extension WidgetData {
    /// Placeholder and gallery content: three projects in different states.
    nonisolated static func sample(on date: Date = .now) -> WidgetData {
        let today = date.startOfDay
        func cp(_ title: String, _ days: Int, done: Bool = false, goals: [(String, Bool)] = [], launch: Bool = false) -> WidgetCheckpoint {
            WidgetCheckpoint(title: title, due: today.adding(days: days), done: done, isLaunch: launch,
                             goals: goals.map { WidgetGoal(title: $0.0, done: $0.1) },
                             goalCount: goals.count, goalsDone: goals.filter(\.1).count)
        }
        func metric(_ key: String, _ title: String, _ symbol: String, _ v: Double, _ f: String, _ d: String, spark: [Double]) -> WidgetMetric {
            WidgetMetric(key: key, title: title, symbol: symbol, value: v, formatted: f, delta: d, deltaPositive: true, spark: spark)
        }
        let habit = WidgetProject(
            id: "sample-habit", name: "Habit Hero", accentHex: 0x58CC02,
            startDate: today.adding(days: -9), buildEnd: today.adding(days: 5), observeEnd: today.adding(days: 33),
            checkpoints: [cp("Checkpoint 1", -6, done: true), cp("Checkpoint 2", -2, done: true),
                          cp("Streak screen", 2, goals: [("Onboarding flow live", true), ("Shareable streak card", false), ("Push reminders", false)]),
                          cp("Ship it", 4, launch: true)],
            metrics: [metric("visits", "Visits", "globe", 9_444, "9,444", "+3.1K", spark: [2.1, 3.0, 3.8, 4.9, 6.0, 7.6, 9.4]),
                      metric("social_views", "Social views", "eye.fill", 41_200, "41.2K", "+12K", spark: [9, 14, 18, 22, 29, 35, 41]),
                      metric("revenue", "Revenue", "dollarsign.circle.fill", 612, "$612.00", "+$240", spark: [120, 180, 260, 330, 410, 520, 612])])
        let pixel = WidgetProject(
            id: "sample-pixel", name: "Pixel Quest", accentHex: 0xA35CFF,
            startDate: today.adding(days: -23), buildEnd: today.adding(days: -9), observeEnd: today.adding(days: 19),
            checkpoints: [cp("Ship it", -10, done: true, launch: true), cp("Traction review", 18, goals: [("1,000 signups", false)])],
            metrics: [metric("visits", "Visits", "globe", 40_600, "40.6K", "+14K", spark: [18, 22, 25, 29, 33, 37, 40.6]),
                      metric("revenue", "Revenue", "dollarsign.circle.fill", 2_439, "$2,439", "+$810", spark: [1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4])])
        let shop = WidgetProject(
            id: "sample-shop", name: "Side Shop", accentHex: 0xFF9600,
            startDate: today.adding(days: -2), buildEnd: today.adding(days: 12), observeEnd: today.adding(days: 40),
            checkpoints: [cp("Checkout", 1, goals: [("Stripe checkout", false), ("Shipping rates", false)])],
            metrics: [metric("visits", "Visits", "globe", 820, "820", "+820", spark: [0, 0, 0, 0, 120, 410, 820])])
        return WidgetData(generatedAt: date, streak: 4, projects: [habit, pixel, shop])
    }
}
