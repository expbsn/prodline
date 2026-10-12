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
    /// When the countdown ends (midnight after the day it's due), as Unix seconds: the relay starts these
    /// with a push, and a plain number decodes the same everywhere.
    var deadlineUnix: Double

    var deadline: Date { Date(timeIntervalSince1970: deadlineUnix) }

    init(projectID: String, milestoneID: String, projectName: String, accentHex: Int, checkpoint: String, deadline: Date) {
        self.projectID = projectID
        self.milestoneID = milestoneID
        self.projectName = projectName
        self.accentHex = accentHex
        self.checkpoint = checkpoint
        self.deadlineUnix = deadline.timeIntervalSince1970.rounded()
    }

    /// The activity runs for the last stretch of the deadline day only.
    static let window: TimeInterval = 4 * 3600
    var windowStart: Date { deadline.addingTimeInterval(-Self.window) }
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
