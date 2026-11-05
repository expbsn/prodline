import Foundation

// A project's plan is a row of stages ("Build", "Beta", "Launch week", "Observe"), each with a planned
// length. The next stage starts when the user confirms the current one done (every checkpoint in it
// finished), not when its days run out: a stage that runs over stays current and shows how far over it
// is, and the stages after it move back. Any stage can end with the keep, pivot or kill call.

/// One stretch of a project's plan.
nonisolated struct Stage: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    /// Planned length in days.
    var days: Int
    /// Ends with the keep, pivot or kill call.
    var decides = false
    /// The day it was confirmed done; nil while current or ahead.
    var finishedAt: Date? = nil

    static let dayRange = 1...120

    /// Projects made before stages (and new users' template): a build, then a decision after watching.
    static func defaults(buildDays: Int, observeDays: Int) -> [Stage] {
        [Stage(name: "Build", days: buildDays), Stage(name: "Observe", days: observeDays, decides: true)]
    }
}

/// A checkpoint planned but not created yet: in the create flow, and kept on drafts until they start.
nonisolated struct PlannedCheckpoint: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var stageID: UUID
    /// Days after its stage starts (0 = the stage's first day).
    var day: Int
    var title: String
    var titleIsCustom = false
    var isLaunch = false
    var goals: [PlannedGoal] = []
}

nonisolated struct PlannedGoal: Codable, Hashable, Sendable {
    var title: String
    var sourceRaw: String
}

/// Where a stage sits in time: its days so far, or as planned from here.
struct StageSpan: Identifiable, Hashable {
    enum State { case done, current, ahead }

    let index: Int
    let stage: Stage
    /// First day.
    let start: Date
    /// The day after the last planned day.
    let plannedEnd: Date
    /// The day after its last day: when it was finished, when it's due (or tomorrow, once it runs over),
    /// or start + length for stages ahead.
    let end: Date
    let state: State

    var id: UUID { stage.id }
    var lastDay: Date { end.adding(days: -1) }
    var plannedLastDay: Date { plannedEnd.adding(days: -1) }
    var length: Int { max(1, Date.days(from: start, to: end)) }

    func contains(_ date: Date) -> Bool { date.startOfDay >= start && date.startOfDay < end }

    /// 1-based day within the stage.
    func day(on date: Date = .now) -> Int { Date.days(from: start, to: date.startOfDay) + 1 }

    /// Days past the planned end (current stage only); 0 while on time.
    func daysOver(on date: Date = .now) -> Int {
        guard state == .current, date.startOfDay >= plannedEnd else { return 0 }
        return Date.days(from: plannedEnd, to: date.startOfDay) + 1
    }

    /// Days left until the planned end, today included (current stage).
    func daysLeft(on date: Date = .now) -> Int { max(0, Date.days(from: date.startOfDay, to: plannedEnd)) }
}

extension Project {
    var stages: [Stage] {
        get { stages(on: .now) }
        set { stagesData = try? JSONEncoder().encode(newValue) }
    }

    /// The saved stages, or (before conversion) Build and Observe as they stand on `date`.
    func stages(on date: Date) -> [Stage] {
        if let data = stagesData, let s = try? JSONDecoder().decode([Stage].self, from: data), !s.isEmpty { return s }
        return legacyStages(on: date)
    }

    var legacyStages: [Stage] { legacyStages(on: .now) }

    /// Build and Observe from the old lengths, with ids derived from the project's so they stay put
    /// until the conversion is saved (StageEngine.migrate). The build counts as done once its days are up.
    func legacyStages(on date: Date) -> [Stage] {
        let buildEnd = startDate.adding(days: buildDays)
        var build = Stage(id: derivedID(1), name: "Build", days: buildDays)
        var observe = Stage(id: derivedID(2), name: "Observe", days: observeDays, decides: true)
        if date.startOfDay >= buildEnd { build.finishedAt = buildEnd }
        if verdict == .kill || verdict == .pivot {
            if build.finishedAt == nil { build.finishedAt = (verdictAt ?? .now).startOfDay }
            observe.finishedAt = (verdictAt ?? .now).startOfDay
        }
        return [build, observe]
    }

    private func derivedID(_ n: Int) -> UUID {
        var bytes = id.uuid
        bytes.15 = bytes.15 &+ UInt8(n)
        return UUID(uuid: bytes)
    }

    var plannedCheckpoints: [PlannedCheckpoint] {
        get { draftPlanData.flatMap { try? JSONDecoder().decode([PlannedCheckpoint].self, from: $0) } ?? [] }
        set { draftPlanData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    // MARK: Timeline

    /// Every stage placed in time, as of `date`.
    func spans(on date: Date = .now) -> [StageSpan] {
        let today = date.startOfDay
        var out: [StageSpan] = []
        var cursor = startDate.startOfDay
        var reachedCurrent = false
        for (i, stage) in stages(on: date).enumerated() {
            let start = cursor
            let plannedEnd = start.adding(days: max(1, stage.days))
            let end: Date
            let state: StageSpan.State
            if !reachedCurrent, let done = stage.finishedAt {
                end = max(done.startOfDay, start)
                state = .done
            } else if !reachedCurrent && !isDraft {
                reachedCurrent = true
                end = today >= start ? max(plannedEnd, today.adding(days: 1)) : plannedEnd
                state = .current
            } else {
                reachedCurrent = true
                end = plannedEnd
                state = .ahead
            }
            out.append(StageSpan(index: i, stage: stage, start: start, plannedEnd: plannedEnd, end: end, state: state))
            cursor = end
        }
        return out
    }

    /// The stage in progress; nil for drafts, before the start and once every stage is done.
    func currentSpan(on date: Date = .now) -> StageSpan? {
        guard !isDraft, date.startOfDay >= startDate else { return nil }
        return spans(on: date).first { $0.state == .current }
    }

    var currentStage: Stage? { currentSpan()?.stage }
    var isFinished: Bool { !isDraft && stages.allSatisfy { $0.finishedAt != nil } }

    /// The stage that ends with the launch: the one holding the launch checkpoint, else the one before the
    /// first decision (or the last stage when nothing decides).
    var launchStageIndex: Int {
        let all = stages
        if let launch = (milestones ?? []).first(where: \.isLaunch), let i = all.firstIndex(where: { $0.id.uuidString == launch.stageID }) {
            return i
        }
        if let i = plannedCheckpoints.first(where: \.isLaunch).flatMap({ c in all.firstIndex { $0.id == c.stageID } }) { return i }
        if let d = all.firstIndex(where: \.decides) { return max(0, d - 1) }
        return max(0, all.count - 1)
    }

    /// The day after the last stage (as planned from today).
    var planEnd: Date { planEnd(on: .now) }
    func planEnd(on date: Date) -> Date { spans(on: date).last?.end ?? startDate }
    /// The day after the launch stage.
    var buildEnd: Date { spans()[safe: launchStageIndex]?.end ?? planEnd }
    var launchDay: Date { buildEnd.adding(days: -1) }
    /// Kept for the code that thinks in two phases: the end of the whole plan.
    var observeEnd: Date { planEnd }

    /// Coarse status for the rest of the app: building until the launch stage is done, observing after.
    func phase(on date: Date = .now) -> Phase {
        if isDraft { return .upcoming }
        let d = date.startOfDay
        if d < startDate { return .upcoming }
        let all = spans(on: date)
        guard let span = all.first(where: { $0.contains(d) }) else {
            return d >= (all.last?.end ?? startDate) ? .finished : .upcoming
        }
        return span.index <= launchStageIndex ? .building : .observing
    }

    var isActive: Bool { currentSpan() != nil }

    /// 1-based day within the current stage.
    var dayInPhase: Int { currentSpan()?.day() ?? 0 }
    /// The current stage's planned length.
    var phaseLength: Int { currentSpan()?.stage.days ?? 0 }

    /// 0...1 across the whole plan.
    var overallProgress: Double {
        let total = Double(max(1, Date.days(from: startDate, to: planEnd)))
        let done = Double(Date.days(from: startDate, to: .now))
        return min(max(done / total, 0), 1)
    }

    var daysLeftInPhase: Int {
        if phase() == .upcoming { return isDraft ? 0 : Date.days(from: .now, to: startDate) }
        return currentSpan()?.daysLeft() ?? 0
    }

    var totalPlannedDays: Int { stages.map(\.days).reduce(0, +) }

    /// "Build · 6d left", "Beta · 2d over", "Starts Nov 8", "Draft", "Done".
    var stageStatus: String {
        if isDraft { return "Draft" }
        if phase() == .upcoming { return "Starts \(startDate.dayMonth)" }
        guard let span = currentSpan() else { return verdict?.pastTense ?? "Done" }
        let over = span.daysOver()
        return over > 0 ? "\(span.stage.name) · \(over)d over" : "\(span.stage.name) · \(span.daysLeft())d left"
    }

    /// "Build · day 3 of 14", for the card and the project header.
    var stageDayText: String {
        if isDraft { return "Draft" }
        if phase() == .upcoming { return "Starts \(startDate.dayMonth)" }
        guard let span = currentSpan() else { return verdict?.pastTense ?? "Done" }
        return "\(span.stage.name) · day \(span.day()) of \(span.stage.days)"
    }

    // MARK: Checkpoints by stage

    func stageIndex(of m: Milestone) -> Int? {
        let all = stages
        if let i = all.firstIndex(where: { $0.id.uuidString == m.stageID }) { return i }
        let s = spans()
        return s.firstIndex { $0.contains(m.dueDate) } ?? (m.dueDate < startDate ? 0 : s.indices.last)
    }

    func milestones(in stage: Stage) -> [Milestone] {
        guard let i = stages.firstIndex(where: { $0.id == stage.id }) else { return [] }
        return sortedMilestones.filter { stageIndex(of: $0) == i }
    }
}
