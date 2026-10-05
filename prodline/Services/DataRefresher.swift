import Foundation
import SwiftData
import SwiftUI
import BackgroundTasks

/// Pulls metrics from every active project.
/// - Foreground: every `AppSettings.refreshSeconds` (default 30 s) while active, plus immediately on activation.
/// - Background: opportunistic BGAppRefresh (iOS decides when; typically 15+ min).
/// - Failing endpoints back off exponentially (30 s … 15 min) or honor `Retry-After`.
@Observable
final class DataRefresher {
    static let minGap: TimeInterval = 10
    static let historyStoreGap: TimeInterval = 15 * 60
    static let maxBackoff: TimeInterval = 15 * 60
    static let backgroundTaskID = "expbsn.app.prodline.refresh"

    enum Status: Equatable {
        case sample
        case live(Date)
        case failing(String, retryAt: Date)
    }

    var latest: [UUID: MetricsPayload] = [:]
    var status: [UUID: Status] = [:]
    var isRefreshing = false
    var lastRefresh: Date?

    private(set) var failures: [UUID: Int] = [:]
    private var nextAttempt: [UUID: Date] = [:]
    private let clientProvider: (Project) -> (client: any MetricsClient, isSample: Bool)

    init(clientProvider: ((Project) -> (client: any MetricsClient, isSample: Bool))? = nil) {
        self.clientProvider = clientProvider ?? Self.defaultClient
    }

    static func defaultClient(for project: Project) -> (client: any MetricsClient, isSample: Bool) {
        if project.hasEndpoint,
           let url = URL(string: project.endpoint.trimmingCharacters(in: .whitespaces)),
           let key = Keychain.get(project.id.uuidString), !key.isEmpty {
            return (RESTMetricsClient(url: url, apiKey: key), false)
        }
        let seed = Int(project.id.uuid.0) * 256 + Int(project.id.uuid.1)
        return (SampleMetricsClient(seed: seed, start: project.startDate), true)
    }

    private struct Job: Sendable {
        let id: UUID
        let client: any MetricsClient
        let isSample: Bool
        let since: Date?
    }

    func refresh(projects: [Project], context: ModelContext, force: Bool = false, now: Date = .now) async {
        guard !isRefreshing else { return }
        if !force, let last = lastRefresh, now.timeIntervalSince(last) < Self.minGap { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let due = projects.filter { p in
            guard p.phase(on: now) == .building || p.phase(on: now) == .observing else { return false }
            return force || (nextAttempt[p.id].map { $0 <= now } ?? true)
        }
        let jobs = due.compactMap { p -> Job? in
            let c = clientProvider(p)
            // Sample numbers can be switched off in Configuration.
            if c.isSample && !AppSettings.sampleData {
                latest[p.id] = nil
                status[p.id] = nil
                return nil
            }
            return Job(id: p.id, client: c.client, isSample: c.isSample, since: p.latestSnapshot?.date)
        }

        let results = await withTaskGroup(of: (UUID, Bool, Result<MetricsPayload, MetricsError>).self) { group in
            for job in jobs {
                group.addTask {
                    do { return (job.id, job.isSample, .success(try await job.client.fetch(since: job.since))) }
                    catch let e as MetricsError { return (job.id, job.isSample, .failure(e)) }
                    catch { return (job.id, job.isSample, .failure(.offline(error.localizedDescription))) }
                }
            }
            var out: [(UUID, Bool, Result<MetricsPayload, MetricsError>)] = []
            for await r in group { out.append(r) }
            return out
        }

        for (id, isSample, result) in results {
            guard let project = due.first(where: { $0.id == id }) else { continue }
            switch result {
            case .success(let payload):
                latest[id] = payload
                failures[id] = 0
                nextAttempt[id] = nil
                status[id] = isSample ? .sample : .live(now)
                store(payload, in: project, context: context)
                if let goals = payload.goals { GoalEngine.syncAPI(goals, project: project, context: context) }
            case .failure(let error):
                let n = (failures[id] ?? 0) + 1
                failures[id] = n
                let delay = error.retryAfter ?? min(30 * pow(2, Double(n - 1)), Self.maxBackoff)
                let retryAt = now.addingTimeInterval(delay)
                nextAttempt[id] = retryAt
                status[id] = .failing(error.localizedDescription, retryAt: retryAt)
            }
        }
        lastRefresh = now
        try? context.save()
    }

    /// Forget everything in memory (used by "Delete all data").
    func reset() {
        latest = [:]; status = [:]; failures = [:]; nextAttempt = [:]; lastRefresh = nil
    }

    func store(_ payload: MetricsPayload, in project: Project, context: ModelContext) {
        let existing = project.snapshots ?? []
        var known = Set(existing.map { Int($0.date.timeIntervalSince1970 / 60) })
        var newest = existing.map(\.date).max()

        // Backfill history the server provides (deduplicated per minute).
        for point in (payload.history ?? []).sorted(by: { $0.asOf < $1.asOf }) {
            let minute = Int(point.asOf.timeIntervalSince1970 / 60)
            guard !known.contains(minute) else { continue }
            known.insert(minute)
            insert(MetricSnapshot(date: point.asOf, visits: point.value(.visits), socialViews: point.value(.socialViews),
                                  revenue: point.value(.revenue), extras: point.metrics.extras), into: project, context: context)
            newest = max(newest ?? point.asOf, point.asOf)
        }

        // Throttle stored live points so the synced history stays small.
        if let newest, payload.asOf.timeIntervalSince(newest) < Self.historyStoreGap { return }
        guard !known.contains(Int(payload.asOf.timeIntervalSince1970 / 60)) else { return }
        insert(MetricSnapshot(date: payload.asOf, visits: payload.value(.visits), socialViews: payload.value(.socialViews),
                              revenue: payload.value(.revenue), extras: payload.extras), into: project, context: context)
    }

    private func insert(_ s: MetricSnapshot, into project: Project, context: ModelContext) {
        context.insert(s)
        s.project = project
    }

    /// Latest known numbers for a project: live poll first, then last stored snapshot.
    func current(for project: Project) -> (visits: Double, social: Double, revenue: Double)? {
        if let p = latest[project.id] { return (p.value(.visits), p.value(.socialViews), p.value(.revenue)) }
        if let s = project.latestSnapshot { return (s.visits, s.socialViews, s.revenue) }
        return nil
    }

    func value(_ key: MetricKey, for project: Project) -> Double? {
        guard let c = current(for: project) else { return nil }
        switch key {
        case .visits: return c.visits
        case .socialViews: return c.social
        case .revenue: return c.revenue
        }
    }

    func extras(for project: Project) -> [(key: String, value: Double)] {
        let dict = latest[project.id]?.extras ?? project.latestSnapshot?.extras ?? [:]
        return dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: Background

    static func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    @MainActor
    static func runBackground(container: ModelContainer) async {
        let context = ModelContext(container)
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        await DataRefresher().refresh(projects: projects, context: context, force: true)
        scheduleBackgroundRefresh()
    }
}
