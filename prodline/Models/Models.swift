import Foundation
import SwiftData
import SwiftUI

// All properties have defaults and relationships are optional so the schema is CloudKit-compatible.

@Model
final class Profile {
    var createdAt: Date = Date.now
    var onboarded: Bool = false
    var xp: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0

    // Custom building scheme
    var buildDays: Int = 14
    var observeDays: Int = 28
    var newProjectEveryDays: Int = 14
    /// Bit (weekday - 1) set => milestone on that weekday (Calendar weekday, Sunday = 1).
    var milestoneWeekdayMask: Int = 34 // Mon + Fri
    var reminderHour: Int = 9
    var remindersEnabled: Bool = true

    init() {}

    var level: Int { xp / 100 + 1 }
    var levelProgress: Double { Double(xp % 100) / 100 }

    func hasWeekday(_ weekday: Int) -> Bool { milestoneWeekdayMask & (1 << (weekday - 1)) != 0 }
    func toggleWeekday(_ weekday: Int) { milestoneWeekdayMask ^= (1 << (weekday - 1)) }
}

enum Phase {
    case upcoming, building, observing, finished

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .building: "Building"
        case .observing: "Observing"
        case .finished: "Finished"
        }
    }

    var color: Color {
        switch self {
        case .upcoming: Theme.inkLight
        case .building: Theme.blue
        case .observing: Theme.orange
        case .finished: Theme.green
        }
    }

    var icon: String {
        switch self {
        case .upcoming: "⏳"
        case .building: "🛠️"
        case .observing: "📈"
        case .finished: "🏁"
        }
    }
}

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🚀"
    var colorIndex: Int = 0
    var startDate: Date = Date.now.startOfDay
    var buildDays: Int = 14
    var observeDays: Int = 28
    /// Metrics endpoint. Empty => sample data. The API key lives in the Keychain.
    var endpoint: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Milestone.project)
    var milestones: [Milestone]? = []
    @Relationship(deleteRule: .cascade, inverse: \MetricSnapshot.project)
    var snapshots: [MetricSnapshot]? = []

    init(name: String, emoji: String, colorIndex: Int, startDate: Date, buildDays: Int, observeDays: Int) {
        self.name = name
        self.emoji = emoji
        self.colorIndex = colorIndex
        self.startDate = startDate.startOfDay
        self.buildDays = buildDays
        self.observeDays = observeDays
    }

    var color: Color { Theme.palette[abs(colorIndex) % Theme.palette.count] }
    var buildEnd: Date { startDate.adding(days: buildDays) }
    var observeEnd: Date { buildEnd.adding(days: observeDays) }

    func phase(on date: Date = .now) -> Phase {
        let d = date.startOfDay
        if d < startDate { return .upcoming }
        if d < buildEnd { return .building }
        if d < observeEnd { return .observing }
        return .finished
    }

    /// 0...1 across build + observe.
    var overallProgress: Double {
        let total = Double(buildDays + observeDays)
        let done = Double(Date.days(from: startDate, to: .now))
        return min(max(done / total, 0), 1)
    }

    var phaseProgress: Double {
        switch phase() {
        case .upcoming: return 0
        case .building: return Double(Date.days(from: startDate, to: .now)) / Double(max(buildDays, 1))
        case .observing: return Double(Date.days(from: buildEnd, to: .now)) / Double(max(observeDays, 1))
        case .finished: return 1
        }
    }

    var daysLeftInPhase: Int {
        switch phase() {
        case .upcoming: Date.days(from: .now, to: startDate)
        case .building: Date.days(from: .now, to: buildEnd)
        case .observing: Date.days(from: .now, to: observeEnd)
        case .finished: 0
        }
    }

    var sortedMilestones: [Milestone] { (milestones ?? []).sorted { $0.dueDate < $1.dueDate } }
    var sortedSnapshots: [MetricSnapshot] { (snapshots ?? []).sorted { $0.date < $1.date } }
    var latestSnapshot: MetricSnapshot? { sortedSnapshots.last }
}

@Model
final class Milestone {
    var id: UUID = UUID()
    var title: String = ""
    var dueDate: Date = Date.now.startOfDay
    var completedAt: Date? = nil
    var missed: Bool = false
    var isLaunch: Bool = false
    var project: Project? = nil

    init(title: String, dueDate: Date, isLaunch: Bool = false) {
        self.title = title
        self.dueDate = dueDate.startOfDay
        self.isLaunch = isLaunch
    }

    var isDone: Bool { completedAt != nil }
    var isOverdue: Bool { !isDone && dueDate < Date.now.startOfDay }
    var isDueToday: Bool { !isDone && dueDate == Date.now.startOfDay }
}

@Model
final class MetricSnapshot {
    var date: Date = Date.now
    var visits: Double = 0
    var socialViews: Double = 0
    var revenue: Double = 0
    var project: Project? = nil

    init(date: Date, visits: Double, socialViews: Double, revenue: Double) {
        self.date = date
        self.visits = visits
        self.socialViews = socialViews
        self.revenue = revenue
    }

    func value(_ key: MetricKey) -> Double {
        switch key {
        case .visits: visits
        case .socialViews: socialViews
        case .revenue: revenue
        }
    }
}
