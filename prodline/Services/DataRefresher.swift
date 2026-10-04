import Foundation
import SwiftData
import SwiftUI
import BackgroundTasks

/// Pulls metrics from every active project.
/// - Foreground: every `foregroundInterval` while the app is active, plus immediately on activation.
/// - Background: opportunistic BGAppRefresh (iOS decides when; typically 15+ min).
@Observable
final class DataRefresher {
    static let foregroundInterval: Duration = .seconds(30)
    static let minGap: TimeInterval = 10
    static let historyStoreGap: TimeInterval = 15 * 60
    static let backgroundTaskID = "expbsn.app.prodline.refresh"

    var latest: [UUID: MetricsPayload] = [:]
    var errors: [UUID: String] = [:]
    var isRefreshing = false
    var lastRefresh: Date?

    private struct Job: Sendable {
        let id: UUID
        let client: any MetricsClient
    }

    static func client(for project: Project) -> any MetricsClient {
        if let url = URL(string: project.endpoint.trimmingCharacters(in: .whitespaces)),
           url.scheme?.hasPrefix("http") == true,
           let key = Keychain.get(project.id.uuidString) {
            return RESTMetricsClient(url: url, apiKey: key)
        }
        return MockMetricsClient(seed: Int(project.id.uuid.0) * 256 + Int(project.id.uuid.1), start: project.startDate)
    }

    func refresh(projects: [Project], context: ModelContext, force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < Self.minGap { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let active = projects.filter { $0.phase() == .building || $0.phase() == .observing }
        let jobs = active.map { Job(id: $0.id, client: Self.client(for: $0)) }

        let results = await withTaskGroup(of: (UUID, MetricsPayload?, String?).self) { group in
            for job in jobs {
                group.addTask {
                    do { return (job.id, try await job.client.fetch(), nil) }
                    catch { return (job.id, nil, error.localizedDescription) }
                }
            }
            var out: [(UUID, MetricsPayload?, String?)] = []
            for await r in group { out.append(r) }
            return out
        }

        for (id, payload, error) in results {
            guard let project = active.first(where: { $0.id == id }) else { continue }
            if let payload {
                latest[id] = payload
                errors[id] = nil
                store(payload, in: project, context: context)
            } else {
                errors[id] = error
            }
        }
        lastRefresh = Date()
        try? context.save()
    }

    private func store(_ payload: MetricsPayload, in project: Project, context: ModelContext) {
        let existing = project.sortedSnapshots
        let known = Set(existing.map { Int($0.date.timeIntervalSince1970 / 60) })

        // Backfill history the server provides.
        for point in payload.history ?? [] where !known.contains(Int(point.asOf.timeIntervalSince1970 / 60)) {
            let s = MetricSnapshot(date: point.asOf, visits: point.value(.visits),
                                   socialViews: point.value(.socialViews), revenue: point.value(.revenue))
            context.insert(s)
            s.project = project
        }

        // Throttle stored live points so the synced history stays small.
        if let last = existing.last, payload.asOf.timeIntervalSince(last.date) < Self.historyStoreGap { return }
        let s = MetricSnapshot(date: payload.asOf, visits: payload.value(.visits),
                               socialViews: payload.value(.socialViews), revenue: payload.value(.revenue))
        context.insert(s)
        s.project = project
    }

    /// Latest known numbers for a project: live poll first, then last stored snapshot.
    func current(for project: Project) -> (visits: Double, social: Double, revenue: Double)? {
        if let p = latest[project.id] { return (p.value(.visits), p.value(.socialViews), p.value(.revenue)) }
        if let s = project.latestSnapshot { return (s.visits, s.socialViews, s.revenue) }
        return nil
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
