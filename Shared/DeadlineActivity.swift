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

    // Activities saved by earlier versions stored `deadline` as a Date; read those too, so an update
    // never strands a running activity it can't decode.
    private enum CodingKeys: String, CodingKey { case projectID, milestoneID, projectName, accentHex, checkpoint, deadlineUnix, deadline }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try c.decode(String.self, forKey: .projectID)
        milestoneID = try c.decode(String.self, forKey: .milestoneID)
        projectName = try c.decode(String.self, forKey: .projectName)
        accentHex = try c.decode(Int.self, forKey: .accentHex)
        checkpoint = try c.decode(String.self, forKey: .checkpoint)
        if let unix = try c.decodeIfPresent(Double.self, forKey: .deadlineUnix) {
            deadlineUnix = unix
        } else {
            deadlineUnix = try c.decode(Date.self, forKey: .deadline).timeIntervalSince1970
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(milestoneID, forKey: .milestoneID)
        try c.encode(projectName, forKey: .projectName)
        try c.encode(accentHex, forKey: .accentHex)
        try c.encode(checkpoint, forKey: .checkpoint)
        try c.encode(deadlineUnix, forKey: .deadlineUnix)
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
