import Foundation
import ActivityKit

/// The Live Activity for a checkpoint due today that still has open goals. The app starts, updates
/// and ends it (Services/LiveActivities.swift); the widget extension draws it (DeadlineLiveActivity.swift).
nonisolated struct DeadlineAttributes: ActivityAttributes {
    var projectID: String
    var milestoneID: String
    var projectName: String
    var accentHex: Int
    var checkpoint: String
    /// The day it's due; the countdown runs to the end of it.
    var due: Date

    var deadline: Date { due.startOfDay.adding(days: 1) }
    var url: URL { URL(string: "prodline://project/\(projectID)")! }
    var initial: String { projectName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }

    nonisolated struct ContentState: Codable, Hashable {
        /// Open goals first, at most a few.
        var goals: [WidgetGoal]
        var goalCount: Int
        var goalsDone: Int

        var progress: Double { goalCount == 0 ? 0 : Double(goalsDone) / Double(goalCount) }
        var allDone: Bool { goalCount > 0 && goalsDone >= goalCount }
        var openCount: Int { goalCount - goalsDone }
    }
}
