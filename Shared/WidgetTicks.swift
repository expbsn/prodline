import Foundation
import AppIntents
import WidgetKit

/// Goals ticked on the home screen. The widget can't reach the app's database, so a tick is queued in
/// the App Group container and shown in the widget straight away; the app applies the queue (and pays
/// the XP) the next time it runs.
nonisolated struct PendingTick: Codable, Equatable, Sendable {
    var goalID: String
    var done: Bool
    var at: Date
}

nonisolated enum WidgetTicks {
    static let didRecord = Notification.Name("WidgetTicks.didRecord")
    private static var url: URL? { SharedStore.container?.appendingPathComponent("pending-ticks.json") }

    static func pending() -> [PendingTick] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingTick].self, from: data)) ?? []
    }

    /// Queues the tick (a later tick of the same goal replaces it) and flips it in the widget data.
    static func record(goalID: String, done: Bool, at date: Date = .now) {
        guard let url else { return }
        var queue = pending().filter { $0.goalID != goalID }
        queue.append(PendingTick(goalID: goalID, done: done, at: date))
        if let data = try? JSONEncoder().encode(queue) { try? data.write(to: url, options: .atomic) }

        guard var widget = SharedStore.read() else { return }
        for p in widget.projects.indices {
            for c in widget.projects[p].checkpoints.indices {
                guard let g = widget.projects[p].checkpoints[c].goals.firstIndex(where: { $0.id == goalID }) else { continue }
                let was = widget.projects[p].checkpoints[c].goals[g].done
                guard was != done else { continue }
                widget.projects[p].checkpoints[c].goals[g].done = done
                widget.projects[p].checkpoints[c].goalsDone += done ? 1 : -1
            }
        }
        SharedStore.write(widget)
    }

    /// Hands the queue over and clears it.
    static func take() -> [PendingTick] {
        let queue = pending()
        if let url, !queue.isEmpty { try? FileManager.default.removeItem(at: url) }
        return queue
    }
}

/// The tick button on a widget goal.
struct ToggleGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick goal"
    static let isDiscoverable = false

    @Parameter(title: "Goal") var goalID: String
    @Parameter(title: "Done") var done: Bool

    init() {}
    init(goalID: String, done: Bool) {
        self.goalID = goalID
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        WidgetTicks.record(goalID: goalID, done: done)
        await MainActor.run { NotificationCenter.default.post(name: WidgetTicks.didRecord, object: nil) }
        return .result()
    }
}
