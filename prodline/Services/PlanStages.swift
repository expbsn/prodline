import Foundation
import CryptoKit

/// Stages from prodline.json: turning the file's list into the project's stages, and placing the file's
/// checkpoints and goals by stage ("day 3 of Beta") as well as by project day or date.
enum PlanStages {
    typealias FileStage = GitHubSnapshot.PlanFile.FileStage

    /// How the file refers to a stage: its id, else its name, compared without case.
    static func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func key(_ f: FileStage) -> String { key(f.id ?? f.name) }

    /// The same stage id on every sync and every device: derived from the project's id and the stage's key.
    static func id(seed: UUID, key: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("\(seed.uuidString)/stage/\(key)".utf8)))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50  // name-based UUID
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// The file's stages as the project's. Stages finished in the app stay finished (matched by id, then by
    /// name), and finished stages the file no longer lists stay at the front, so past days don't move.
    static func merge(_ file: [FileStage], seed: UUID, current: [Stage]) -> [Stage] {
        var out = file.map { f in
            Stage(id: id(seed: seed, key: key(f)), name: f.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  days: min(max(f.days, Stage.dayRange.lowerBound), Stage.dayRange.upperBound), decides: f.decides ?? false)
        }
        var used = Set<UUID>()
        for i in out.indices {
            let match = current.first { $0.id == out[i].id && !used.contains($0.id) }
                ?? current.first { !used.contains($0.id) && key($0.name) == key(out[i].name) }
            if let match {
                used.insert(match.id)
                out[i].finishedAt = match.finishedAt
            }
        }
        let ids = Set(out.map(\.id))
        let past = current.filter { $0.finishedAt != nil && !used.contains($0.id) && !ids.contains($0.id) }
        return past + out
    }

    /// The span a file's stage reference points at: by derived id, then by name.
    static func span(_ ref: String, in spans: [StageSpan], seed: UUID) -> StageSpan? {
        let k = key(ref)
        guard !k.isEmpty else { return nil }
        let wanted = id(seed: seed, key: k)
        return spans.first { $0.stage.id == wanted } ?? spans.first { key($0.stage.name) == k }
    }

    /// Where an entry in the file falls. `stage` + `day`: that day of the stage (its last day without a day,
    /// clamped to the stage); `day` alone: that day of the project; else `due`.
    static func place(stage: String?, day: Int?, due: Date?, spans: [StageSpan], start: Date, seed: UUID)
        -> (date: Date, span: StageSpan?)? {
        if let stage, let span = span(stage, in: spans, seed: seed) {
            let d = min(max(day ?? span.stage.days, 1), max(1, span.stage.days))
            return (span.start.adding(days: d - 1), span)
        }
        if let day { return (start.startOfDay.adding(days: max(day, 1) - 1), nil) }
        if let due { return (due.startOfDay, nil) }
        return nil
    }

    /// The span a date falls in (the first before the start, the last after the end).
    static func span(containing date: Date, in spans: [StageSpan]) -> StageSpan? {
        spans.first { $0.contains(date) } ?? (spans.first.map { date < $0.start } == true ? spans.first : spans.last)
    }

    /// The file's checkpoints as a plan, for the create flow before the project exists.
    static func plannedCheckpoints(_ plan: GitHubSnapshot.PlanFile, stages: [Stage], start: Date, seed: UUID) -> [PlannedCheckpoint] {
        let spans = Project.previewSpans(stages, start: start)
        var seen = Set<Date>()
        return (plan.checkpoints ?? []).compactMap { c -> (Date, PlannedCheckpoint)? in
            guard let at = place(stage: c.stage, day: c.day, due: c.due, spans: spans, start: start, seed: seed),
                  let span = at.span ?? span(containing: at.date, in: spans), seen.insert(at.date).inserted else { return nil }
            let day = min(max(0, Date.days(from: span.start, to: at.date)), max(0, span.stage.days - 1))
            let title = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return (at.date, PlannedCheckpoint(stageID: span.stage.id, day: day, title: title.isEmpty ? "Checkpoint" : title,
                                               titleIsCustom: !title.isEmpty))
        }
        .sorted { $0.0 < $1.0 }.map(\.1)
    }
}
