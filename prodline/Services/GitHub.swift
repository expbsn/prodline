import Foundation
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

    var description: String
    var readme: String
    var milestones: [Milestone]
    var issues: [Issue]
    var lastCommit: Date?
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

    func fetch() async throws -> GitHubSnapshot {
        struct Repo: Decodable { var description: String?; var pushed_at: Date? }
        struct Commit: Decodable { struct Inner: Decodable { struct Author: Decodable { var date: Date? }; var committer: Author? }; var commit: Inner }

        let repoInfo = try decode(Repo.self, try await get(""))
        async let readmeData = try? get("/readme", accept: "application/vnd.github.raw+json")
        async let milestonesData = get("/milestones", query: [.init(name: "state", value: "all"), .init(name: "per_page", value: "50")])
        async let issuesData = get("/issues", query: [.init(name: "state", value: "all"), .init(name: "per_page", value: "100")])
        async let commitsData = try? get("/commits", query: [.init(name: "per_page", value: "1")])

        let milestones = try decode([GitHubSnapshot.Milestone].self, try await milestonesData)
        let issues = try decode([GitHubSnapshot.Issue].self, try await issuesData).filter { $0.pull_request == nil }
        let readme = (await readmeData).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let lastCommit = (await commitsData).flatMap { try? decode([Commit].self, $0).first?.commit.committer?.date }
        return GitHubSnapshot(description: repoInfo.description ?? "", readme: readme,
                              milestones: milestones, issues: issues, lastCommit: lastCommit ?? repoInfo.pushed_at)
    }
}

/// Polls linked repos (much less often than metrics: GitHub's unauthenticated limit is 60 req/h).
@Observable
final class GitHubService {
    static let interval: TimeInterval = 10 * 60

    var snapshots: [UUID: GitHubSnapshot] = [:]
    var errors: [UUID: String] = [:]
    private var lastFetch: [UUID: Date] = [:]

    /// The API base; DEBUG builds can point it at the mock server.
    static var base: URL {
        UserDefaults.standard.string(forKey: "githubAPIBase").flatMap(URL.init(string:)) ?? GitHubClient.defaultBase
    }

    static func client(for project: Project) -> GitHubClient? {
        guard let ref = GitHubRepoRef(project.githubRepo) else { return nil }
        return GitHubClient(repo: ref, token: Keychain.get("gh-" + project.id.uuidString), base: base)
    }

    /// Returns the projects whose snapshot changed.
    @discardableResult
    func refresh(projects: [Project], force: Bool = false, now: Date = .now) async -> [Project] {
        var changed: [Project] = []
        for p in projects where p.isActive || p.phase() == .upcoming {
            guard let client = Self.client(for: p) else { continue }
            if !force, let last = lastFetch[p.id], now.timeIntervalSince(last) < Self.interval { continue }
            lastFetch[p.id] = now
            do {
                let snap = try await client.fetch()
                errors[p.id] = nil
                if snapshots[p.id] != snap { changed.append(p) }
                snapshots[p.id] = snap
                p.lastCommitAt = snap.lastCommit
            } catch {
                errors[p.id] = error.localizedDescription
            }
        }
        return changed
    }
}
