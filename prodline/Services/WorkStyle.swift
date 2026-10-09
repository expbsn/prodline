import Foundation
import UserNotifications

/// When someone works on their side projects, picked in onboarding. It times the deadline reminder,
/// the "still time today" nudge, the streak nudge and the weekly wrap.
enum WorkStyle: String, CaseIterable, Identifiable {
    case earlyBird, afterHours, nightOwl, weekendWarrior

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earlyBird: "Early bird"
        case .afterHours: "After hours"
        case .nightOwl: "Night owl"
        case .weekendWarrior: "Weekend warrior"
        }
    }

    var blurb: String {
        switch self {
        case .earlyBird: "Coffee, code, then the day job."
        case .afterHours: "Day job first, side project after dinner."
        case .nightOwl: "Best ideas come after midnight. Allegedly."
        case .weekendWarrior: "Saturdays are for shipping."
        }
    }

    var symbol: String {
        switch self {
        case .earlyBird: "sunrise.fill"
        case .afterHours: "sunset.fill"
        case .nightOwl: "moon.stars.fill"
        case .weekendWarrior: "calendar"
        }
    }

    var hex: Int {
        switch self {
        case .earlyBird: 0xFF9600
        case .afterHours: 0xFF4B4B
        case .nightOwl: 0x5850EC
        case .weekendWarrior: 0x58CC02
        }
    }

    /// Deadline-day reminder.
    var reminderHour: Int {
        switch self {
        case .earlyBird: 7
        case .afterHours: 18
        case .nightOwl: 21
        case .weekendWarrior: 9
        }
    }

    /// "Still time today" and the streak nudge, near the end of the usual window.
    var nudgeHour: Int {
        switch self {
        case .earlyBird: 12
        case .afterHours: 21
        case .nightOwl: 23
        case .weekendWarrior: 16
        }
    }

    /// Weekly wrap, on Sunday.
    var wrapHour: Int {
        switch self {
        case .earlyBird: 9
        case .afterHours, .weekendWarrior: 18
        case .nightOwl: 21
        }
    }

    /// Weekend warriors get checkpoints on Saturday and Sunday.
    static let weekendMask = (1 << 6) | (1 << 0)
}

extension Profile {
    var workStyle: WorkStyle? {
        get { WorkStyle(rawValue: workStyleRaw) }
        set { workStyleRaw = newValue?.rawValue ?? "" }
    }

    /// Sets every time from the style; weekend warriors also get weekend checkpoints. `wrap: false`
    /// leaves the device-wide wrap hour alone (tests).
    func apply(_ style: WorkStyle, wrap: Bool = true) {
        workStyle = style
        reminderHour = style.reminderHour
        nudgeHour = style.nudgeHour
        if wrap { WeeklyReview.hour = style.wrapHour }
        if style == .weekendWarrior {
            milestoneWeekdayMask = WorkStyle.weekendMask
        } else if milestoneWeekdayMask == WorkStyle.weekendMask {
            milestoneWeekdayMask = 34 // back to Mon + Fri
        }
    }
}

/// "Your flame goes out tonight": at the nudge hour on days nothing has counted yet. Scheduled a few
/// days ahead (the app may not open), and today's is dropped once today counts.
enum StreakNudge {
    static let days = 3
    static func id(_ d: Int) -> String { "streak-nudge-\(d)" }

    static func schedule(_ profile: Profile, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<days).map(id))
        guard profile.remindersEnabled, profile.streak > 0 else { return }
        let litToday = Streak.isActiveToday(profile, now: now)
        for d in 0..<days {
            if d == 0 && litToday { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: now.adding(days: d))
            comps.hour = profile.nudgeHour
            guard let fire = Calendar.current.date(from: comps), fire > now else { continue }
            // Tomorrow's streak is today's +1 if today counts, otherwise it's already gone by then.
            let streak = litToday ? profile.streak + d - 1 : (d == 0 ? profile.streak : 0)
            guard streak > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Your \(streak)-day streak ends tonight 🔥"
            content.body = ["One tiny tick keeps it alive.", "A single goal is enough. You know you want to.",
                            "Don't let the flame go out on a technicality."][d % 3]
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id(d), content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
