import Foundation
import FoundationModels

@Generable(description: "Concrete goals for each checkpoint of a software project's build phase")
struct CheckpointPlan {
    @Guide(description: "One entry per checkpoint that should get goals")
    var checkpoints: [CheckpointGoals]
}

@Generable
struct CheckpointGoals {
    @Guide(description: "The checkpoint number from the list, starting at 1")
    var checkpoint: Int
    @Guide(description: "Short, concrete, verifiable deliverables of 2 to 6 words, each starting with a verb", .count(1...3))
    var goals: [String]
}

/// Drafts checkpoint goals with Apple's on-device model (Apple Intelligence). Nothing leaves the device.
enum GoalPlanner {
    struct Deadline: Sendable {
        let title: String
        let date: Date
    }

    nonisolated static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Available on this device and switched on in Configuration.
    static var isEnabled: Bool { isAvailable && AppSettings.suggestions }

    static var unavailableReason: String {
        if isAvailable && !AppSettings.suggestions { return "Suggestions are turned off in Me → Configuration." }
        switch SystemLanguageModel.default.availability {
        case .available: return ""
        case .unavailable(.deviceNotEligible): return "This iPhone doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to get suggested goals."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again in a bit."
        case .unavailable: return "On-device AI isn't available right now."
        }
    }

    static func prompt(name: String, details: String, buildDays: Int, deadlines: [Deadline], github: GitHubSnapshot?) -> String {
        var s = """
        Project: \(name)
        Description: \(details.isEmpty ? "(none)" : details)
        Build phase: \(buildDays) days, then the project launches and its traction is observed.

        Deadlines in order:
        """
        for (i, d) in deadlines.enumerated() {
            s += "\n\(i + 1). \(d.title) on \(d.date.formatted(.dateTime.weekday(.wide).month().day()))"
        }
        if let gh = github {
            if !gh.description.isEmpty { s += "\n\nRepository description: \(gh.description)" }
            let open = gh.issues.filter { !$0.isClosed }.prefix(15).map { "- \($0.title)" }
            if !open.isEmpty { s += "\nOpen issues:\n" + open.joined(separator: "\n") }
            if !gh.readme.isEmpty { s += "\nREADME (excerpt):\n" + String(gh.readme.prefix(1500)) }
        }
        s += """

        \nSpread the work so it builds up to a shippable product on the "Ship it" deadline.
        Give goals for every checkpoint and for "Ship it". Skip "Traction review".
        """
        return s
    }

    /// Returns goals keyed by 1-based deadline position.
    static func draft(name: String, details: String, buildDays: Int, deadlines: [Deadline],
                      github: GitHubSnapshot?) async throws -> [Int: [String]] {
        let session = LanguageModelSession(instructions: """
            You plan small software projects for a solo builder who ships a new project every few weeks. \
            Goals must be concrete outcomes someone can check off (e.g. "Ship landing page", "Add Stripe checkout"), \
            not vague activities. Respect the order: early checkpoints cover foundations, later ones polish and launch.
            """)
        let response = try await session.respond(
            to: prompt(name: name, details: details, buildDays: buildDays, deadlines: deadlines, github: github),
            generating: CheckpointPlan.self)
        var out: [Int: [String]] = [:]
        for c in response.content.checkpoints where (1...deadlines.count).contains(c.checkpoint) {
            out[c.checkpoint, default: []] += c.goals.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        // The review is measured by traction targets, not by tasks.
        out[deadlines.count] = nil
        return out
    }
}
