import Foundation
import SwiftData
import SwiftUI
import UIKit

// All properties have defaults and relationships are optional so the schema is CloudKit-compatible.

@Model
final class Profile {
    var createdAt: Date = Date.now
    var onboarded: Bool = false
    var xp: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    var completedOnTime: Int = 0
    var completedLate: Int = 0

    // Custom building scheme
    var buildDays: Int = 14
    var observeDays: Int = 28
    var newProjectEveryDays: Int = 14
    /// Bit (weekday - 1) set => checkpoint on that weekday (Calendar weekday, Sunday = 1).
    var milestoneWeekdayMask: Int = 34 // Mon + Fri
    var reminderHour: Int = 9
    var remindersEnabled: Bool = true

    init() {}

    var level: Int { xp / 100 + 1 }
    var levelProgress: Double { Double(xp % 100) / 100 }
    var onTimeRate: Double? {
        let total = completedOnTime + completedLate
        return total == 0 ? nil : Double(completedOnTime) / Double(total)
    }

    func hasWeekday(_ weekday: Int) -> Bool { milestoneWeekdayMask & (1 << (weekday - 1)) != 0 }
    func toggleWeekday(_ weekday: Int) { milestoneWeekdayMask ^= (1 << (weekday - 1)) }
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

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var accentHex: Int = 0x58CC02
    /// Square JPEG cover. Its dominant color usually becomes the accent.
    @Attribute(.externalStorage) var coverImage: Data? = nil
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

    init(name: String, accentHex: Int, startDate: Date, buildDays: Int, observeDays: Int) {
        self.name = name
        self.accentHex = accentHex
        self.startDate = startDate.startOfDay
        self.buildDays = buildDays
        self.observeDays = observeDays
    }

    var accent: Accent { Accent(hex: accentHex) }
    var initial: String { name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }
    var cover: UIImage? { CoverCache.image(coverImage, key: id.uuidString) }

    var buildEnd: Date { startDate.adding(days: buildDays) }
    var observeEnd: Date { buildEnd.adding(days: observeDays) }
    var launchDay: Date { buildEnd.adding(days: -1) }

    func phase(on date: Date = .now) -> Phase {
        let d = date.startOfDay
        if d < startDate { return .upcoming }
        if d < buildEnd { return .building }
        if d < observeEnd { return .observing }
        return .finished
    }

    var isActive: Bool { phase() == .building || phase() == .observing }

    /// 1-based day within the current phase.
    var dayInPhase: Int {
        switch phase() {
        case .upcoming: 0
        case .building: Date.days(from: startDate, to: .now) + 1
        case .observing: Date.days(from: buildEnd, to: .now) + 1
        case .finished: observeDays
        }
    }

    var phaseLength: Int { phase() == .observing ? observeDays : buildDays }

    /// 0...1 across build + observe.
    var overallProgress: Double {
        let total = Double(buildDays + observeDays)
        let done = Double(Date.days(from: startDate, to: .now))
        return min(max(done / total, 0), 1)
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
    var nextMilestone: Milestone? { sortedMilestones.first { !$0.isDone } }
    var sortedSnapshots: [MetricSnapshot] { (snapshots ?? []).sorted { $0.date < $1.date } }
    var latestSnapshot: MetricSnapshot? { (snapshots ?? []).max { $0.date < $1.date } }

    var hasEndpoint: Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else { return false }
        return url.scheme?.hasPrefix("http") == true && url.host() != nil
    }
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
    func isOverdue(on now: Date = .now) -> Bool { !isDone && dueDate < now.startOfDay }
    var isOverdue: Bool { isOverdue() }
    var isDueToday: Bool { !isDone && dueDate == Date.now.startOfDay }
    var completedOnTime: Bool { completedAt.map { $0.startOfDay <= dueDate } ?? false }
}

@Model
final class MetricSnapshot {
    var date: Date = Date.now
    var visits: Double = 0
    var socialViews: Double = 0
    var revenue: Double = 0
    /// Any non-standard metrics the endpoint reports (e.g. "signups").
    var extras: [String: Double] = [:]
    var project: Project? = nil

    init(date: Date, visits: Double, socialViews: Double, revenue: Double, extras: [String: Double] = [:]) {
        self.date = date
        self.visits = visits
        self.socialViews = socialViews
        self.revenue = revenue
        self.extras = extras
    }

    func value(_ key: MetricKey) -> Double {
        switch key {
        case .visits: visits
        case .socialViews: socialViews
        case .revenue: revenue
        }
    }
}
