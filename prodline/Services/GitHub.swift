import Foundation
import OSLog
import SwiftData
import SwiftUI

/// "owner/name", parsed from either that form or a github.com URL.
nonisolated struct GitHubRepoRef: Equatable, Sendable {
    let owner: String
    let name: String

    var slug: String { "\(owner)/\(name)" }

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www.", "github.com/"] where s.lowercased().hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2,
              parts[0].range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil,
              parts[1].range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { return nil }
        owner = parts[0]
        name = parts[1]
    }
}

/// Everything Prodline reads from a repo in one pass.
nonisolated struct GitHubSnapshot: Sendable, Equatable {
    struct Milestone: Codable, Sendable, Equatable {
        var number: Int
        var title: String
        var state: String
        var due_on: Date?
    }
    struct Issue: Codable, Sendable, Equatable {
        struct Label: Codable, Sendable, Equatable { var name: String }
        struct MilestoneRef: Codable, Sendable, Equatable { var number: Int }
        struct PullRef: Codable, Sendable, Equatable { var url: String? }
        var number: Int
        var title: String
        var state: String
        var html_url: String
        var labels: [Label]
        var milestone: MilestoneRef?
        var pull_request: PullRef?

        var isClosed: Bool { state == "closed" }
        var isPlanned: Bool { milestone != nil || labels.contains { $0.name.lowercased() == "prodline" } }
    }

    /// `prodline.json` in the repo root: a goal plan maintained by hand or by a coding agent.
    struct PlanFile: Codable, Sendable, Equatable {
        /// Names a checkpoint, placed the same way as goals (by position or by date).
        struct Checkpoint: Codable, Sendable, Equatable {
            var title: String
            var checkpoint: Int?
            var due: Date?
        }
        var version: Int?
        var checkpoints: [Checkpoint]? = nil
        var goals: [MetricsPayload.RemoteGoal]
    }

    var description: String
    var readme: String
    var milestones: [Milestone]
    var issues: [Issue]
    var lastCommit: Date?
    /// nil when the repo has no prodline.json.
    var planFile: PlanFile? = nil
    /// Commit times since the project's start (only when asked for, newest first, up to 300).
    var commitDates: [Date] = []
    /// Set when prodline.json exists but can't be read; existing file goals are kept meanwhile.
    var planFileError: String? = nil
}

nonisolated enum GitHubError: LocalizedError, Equatable {
    case badRepo, notFound, unauthorized, rateLimited, http(Int), offline

    var errorDescription: String? {
        switch self {
        case .badRepo: "Use the form owner/repo or a github.com link."
        case .notFound: "Repo not found. For private repos, add a token."
        case .unauthorized: "GitHub rejected the token."
        case .rateLimited: "GitHub rate limit reached. Adding a token raises it."
        case .http(let c): "GitHub answered \(c)."
        case .offline: "Can't reach GitHub."
        }
    }
}

nonisolated struct GitHubClient: Sendable {
    static let defaultBase = URL(string: "https://api.github.com")!

    let repo: GitHubRepoRef
    var token: String?
    var base: URL = defaultBase
    var session: URLSession = .shared

    private func get(_ path: String, query: [URLQueryItem] = [], accept: String = "application/vnd.github+json") async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent("repos/\(repo.owner)/\(repo.name)\(path)"),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Prodline/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw GitHubError.offline }
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw GitHubError.unauthorized
        case 403 where http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0", 429: throw GitHubError.rateLimited
        case 404: throw GitHubError.notFound
        default: throw GitHubError.http(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try MetricsPayload.decoder().decode(type, from: data)
    }

    /// Result of the cheap "did anything change?" probe.
    struct HeadCheck: Sendable, Equatable {
        var sha: String?        // nil when unchanged (304)
        var etag: String?
        var unchanged: Bool
        var rateRemaining: Int?
    }

    /// Conditional request for the latest commit. A 304 means nothing changed and, per GitHub,
    /// doesn't count against the rate limit, so this can run every refresh tick.
    func headCommit(etag: String?) async throws -> HeadCheck {
        var comps = URLComponents(url: base.appendingPathComponent("repos/\(repo.owner)/\(repo.name)/commits"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        var req = URLRequest(url: comps.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Prodline/1.0", forHTTPHeaderField: "User-Agent")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw GitHubError.offline }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.offline }
        let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Int.init)
        switch http.statusCode {
        case 304:
            return HeadCheck(sha: nil, etag: etag, unchanged: true, rateRemaining: remaining)
        case 200..<300:
            struct C: Decodable { var sha: String }
            let sha = (try? JSONDecoder().decode([C].self, from: data))?.first?.sha
            return HeadCheck(sha: sha, etag: http.value(forHTTPHeaderField: "ETag"), unchanged: false, rateRemaining: remaining)
        case 401: throw GitHubError.unauthorized
        case 403, 429: throw GitHubError.rateLimited
        case 404: throw GitHubError.notFound
        default: throw GitHubError.http(http.statusCode)
        }
    }

    /// Commit times since `since`, newest first; up to three pages of 100.
    func commitDates(since: Date) async -> [Date] {
        struct Commit: Decodable { struct Inner: Decodable { struct Author: Decodable { var date: Date? }; var committer: Author? }; var commit: Inner }
        var out: [Date] = []
        for page in 1...3 {
            guard let data = try? await get("/commits", query: [.init(name: "since", value: MetricsPayload.iso(since)),
                                                                .init(name: "per_page", value: "100"),
                                                                .init(name: "page", value: "\(page)")]),
                  let batch = try? decode([Commit].self, data) else { break }
            out += batch.compactMap { $0.commit.committer?.date }
            if batch.count < 100 { break }
        }
        return out
    }

    func fetch(commitsSince: Date? = nil) async throws -> GitHubSnapshot {
        struct Repo: Decodable { var description: String?; var pushed_at: Date? }
        struct Commit: Decodable { struct Inner: Decodable { struct Author: Decodable { var date: Date? }; var committer: Author? }; var commit: Inner }

        let repoInfo = try decode(Repo.self, try await get(""))
        async let readmeData = try? get("/readme", accept: "application/vnd.github.raw+json")
        async let milestonesData = get("/milestones", query: [.init(name: "state", value: "all"), .init(name: "per_page", value: "50")])
        async let issuesData = get("/issues", query: [.init(name: "state", value: "all"), .init(name: "per_page", value: "100")])
        async let commitsData = try? get("/commits", query: [.init(name: "per_page", value: "1")])
        async let planData = try? get("/contents/prodline.json", accept: "application/vnd.github.raw+json")

        let milestones = try decode([GitHubSnapshot.Milestone].self, try await milestonesData)
        let issues = try decode([GitHubSnapshot.Issue].self, try await issuesData).filter { $0.pull_request == nil }
        let readme = (await readmeData).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let lastCommit = (await commitsData).flatMap { try? decode([Commit].self, $0).first?.commit.committer?.date }
        var plan: GitHubSnapshot.PlanFile?
        var planError: String?
        if let data = await planData {
            do { plan = try decode(GitHubSnapshot.PlanFile.self, data) }
            catch { planError = "prodline.json isn't valid: \(Self.describe(error))" }
        }
        let log = commitsSince != nil ? await commitDates(since: commitsSince!) : []
        return GitHubSnapshot(description: repoInfo.description ?? "", readme: readme,
                              milestones: milestones, issues: issues, lastCommit: lastCommit ?? repoInfo.pushed_at,
                              planFile: plan, commitDates: log, planFileError: planError)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): return "missing \"\(key.stringValue)\""
        case DecodingError.typeMismatch(_, let ctx), DecodingError.valueNotFound(_, let ctx):
            return "wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case DecodingError.dataCorrupted(let ctx): return ctx.debugDescription
        default: return "not valid JSON"
        }
    }
}

/// Polls linked repos (much less often than metrics: GitHub's unauthenticated limit is 60 req/h).
/// Keeps linked repos in sync.
/// - Full sync (issues, README, prodline.json) every `AppSettings.githubMinutes` (default 10).
/// - Between those, a conditional "latest commit" probe: a new commit triggers a full sync right away.
///   With a token (5,000 req/h) it runs every 25 s; without one (60 req/h, and unauthenticated 304s
///   still count) every 2 min, and it pauses when the remaining quota runs low.
@Observable
final class GitHubService {
    static var interval: TimeInterval { TimeInterval(AppSettings.githubMinutes * 60) }
    static func headCheckGap(authenticated: Bool) -> TimeInterval { authenticated ? 25 : 120 }

    var snapshots: [UUID: GitHubSnapshot] = [:]
    var errors: [UUID: String] = [:]
    private var lastFetch: [UUID: Date] = [:]
    private var lastHeadCheck: [UUID: Date] = [:]
    private var etags: [UUID: String] = [:]
    private(set) var headSHA: [UUID: String] = [:]
    /// GitHub's remaining quota from the last response; the probe pauses when it runs low.
    private(set) var rateRemaining: Int?

    /// Owner reserved for the mock server's fake repos (demo/side-shop).
    static let demoOwner = "demo"

    /// Real repos always talk to api.github.com; only the demo's fake repos go to the mock server.
    static func base(for ref: GitHubRepoRef) -> URL {
        guard ref.owner == demoOwner,
              let mock = UserDefaults.standard.string(forKey: "githubAPIBase").flatMap(URL.init(string:))
        else { return GitHubClient.defaultBase }
        return mock
    }

    static func client(for project: Project) -> GitHubClient? {
        guard let ref = GitHubRepoRef(project.githubRepo) else { return nil }
        return GitHubClient(repo: ref, token: Keychain.get("gh-" + project.id.uuidString), base: base(for: ref))
    }

    func reset() {
        snapshots = [:]; errors = [:]; lastFetch = [:]; lastHeadCheck = [:]; etags = [:]; headSHA = [:]
    }

    /// True when the repo has a commit we haven't synced yet.
    private func hasNewCommit(_ p: Project, client: GitHubClient, now: Date) async -> Bool {
        guard AppSettings.commitWatch, (rateRemaining ?? 60) > 10 else { return false }
        let gap = Self.headCheckGap(authenticated: !(client.token ?? "").isEmpty)
        if let last = lastHeadCheck[p.id], now.timeIntervalSince(last) < gap { return false }
        lastHeadCheck[p.id] = now
        guard let head = try? await client.headCommit(etag: etags[p.id]) else { return false }
        rateRemaining = head.rateRemaining ?? rateRemaining
        if head.unchanged { return false }
        etags[p.id] = head.etag
        defer { if let sha = head.sha { headSHA[p.id] = sha } }
        // First probe only records the baseline; the full sync already has this state.
        guard let known = headSHA[p.id] else { return false }
        return head.sha != nil && head.sha != known
    }

    static let log = Logger(subsystem: "expbsn.app.prodline", category: "github")
    /// Sync diagnostics: unified log, plus stdout so `devicectl … --console` shows it.
    static func trace(_ message: String) {
        log.notice("\(message, privacy: .public)")
        print("[github] \(message)")
    }

    /// Returns the projects whose snapshot changed.
    @discardableResult
    func refresh(projects: [Project], force: Bool = false, now: Date = .now) async -> [Project] {
        var changed: [Project] = []
        for p in projects where p.isActive || p.phase() == .upcoming {
            guard let client = Self.client(for: p) else { continue }
            Self.trace("refresh \(p.name) repo=\(p.githubRepo) phase=\(p.phase()) due=\(force || (self.lastFetch[p.id].map { now.timeIntervalSince($0) >= Self.interval } ?? true))")
            let due = force || (lastFetch[p.id].map { now.timeIntervalSince($0) >= Self.interval } ?? true)
            if !due {
                let pushed = await hasNewCommit(p, client: client, now: now)
                if !pushed { continue }
            }
            lastFetch[p.id] = now
            do {
                let snap = try await client.fetch(commitsSince: p.startDate)
                errors[p.id] = nil
                if snapshots[p.id] != snap { changed.append(p) }
                snapshots[p.id] = snap
                p.lastCommitAt = snap.lastCommit
                let days = Momentum.dailyCounts(snap.commitDates)
                if days != p.commitDays { p.commitDays = days }
                Self.trace("fetched \(p.name): plan=\(snap.planFile?.goals.count ?? -1) planError=\(snap.planFileError ?? "-")")
            } catch {
                errors[p.id] = error.localizedDescription
                Self.trace("fetch failed \(p.name): \(error.localizedDescription)")
            }
        }
        return changed
    }
}
