import Foundation
import SwiftData
import Testing
@testable import prodline

/// End-to-end tests against MockProject/server.py.
/// Run with:  TEST_RUNNER_PRODLINE_MOCK_SERVER=http://127.0.0.1:8787 xcodebuild test …
enum MockServer {
    static let base: String? = ProcessInfo.processInfo.environment["PRODLINE_MOCK_SERVER"]
    static func url(_ slug: String, _ query: String = "") -> URL {
        URL(string: "\(base!)/projects/\(slug)/metrics\(query)")!
    }
    static func post(_ slug: String, key: String, body: String) async throws {
        var req = URLRequest(url: URL(string: "\(base!)/projects/\(slug)/events")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data(body.utf8)
        _ = try await URLSession.shared.data(for: req)
    }
}

@MainActor
@Suite("Mock server (integration)", .enabled(if: MockServer.base != nil), .serialized)
struct MockServerTests {
    @Test func fullPayloadWithHistoryAndCustomMetric() async throws {
        let p = try await RESTMetricsClient(url: MockServer.url("habit-hero"), apiKey: "hh_live_demo").fetch(since: nil)
        #expect(p.schemaVersion == 1)
        #expect(p.value(.visits) > 0)
        #expect(p.value(.revenue) > 0)
        #expect(p.extras["signups"] != nil)
        let history = try #require(p.history)
        #expect(history.count > 100 && history.count <= 169) // hourly, 7 days
        // History is cumulative: never decreases.
        let visits = history.map { $0.value(.visits) }
        #expect(zip(visits, visits.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(visits.last! <= p.value(.visits))
    }

    @Test func sinceLimitsHistory() async throws {
        let client = RESTMetricsClient(url: MockServer.url("pixel-quest"), apiKey: "pq_live_demo")
        let p = try await client.fetch(since: Date.now.addingTimeInterval(-3 * 3600))
        #expect((p.history?.count ?? 0) <= 3)
    }

    @Test func wrongKeyIsUnauthorized() async {
        await #expect(throws: MetricsError.unauthorized) {
            try await RESTMetricsClient(url: MockServer.url("habit-hero"), apiKey: "nope").fetch(since: nil)
        }
    }

    @Test func unknownProjectIsNotFound() async {
        await #expect(throws: MetricsError.notFound) {
            try await RESTMetricsClient(url: MockServer.url("ghost"), apiKey: "x").fetch(since: nil)
        }
    }

    @Test func forcedFailures() async {
        await #expect(throws: MetricsError.rateLimited(retryAfter: 5)) {
            try await RESTMetricsClient(url: MockServer.url("habit-hero", "?fail=429"), apiKey: "hh_live_demo").fetch(since: nil)
        }
        await #expect(throws: MetricsError.server(500)) {
            try await RESTMetricsClient(url: MockServer.url("habit-hero", "?fail=500"), apiKey: "hh_live_demo").fetch(since: nil)
        }
        do {
            _ = try await RESTMetricsClient(url: MockServer.url("habit-hero", "?fail=200"), apiKey: "hh_live_demo").fetch(since: nil)
            Issue.record("expected bad payload")
        } catch let e as MetricsError {
            if case .badPayload = e {} else { Issue.record("wrong error \(e)") }
        } catch { Issue.record("\(error)") }
    }

    @Test func flakyProjectFailsSometimes() async {
        let client = RESTMetricsClient(url: MockServer.url("flaky-app"), apiKey: "fa_live_demo")
        var ok = 0, failed = 0
        for _ in 0..<20 {
            do { _ = try await client.fetch(since: nil); ok += 1 } catch { failed += 1 }
        }
        #expect(ok > 0 && failed > 0)
    }

    @Test func probeReportsLatencyAndMetrics() async {
        let r = await ConnectionProbe.run(endpoint: MockServer.url("side-shop").absoluteString, apiKey: "ss_live_demo")
        guard case let .ok(latency, metrics, history) = r else { Issue.record("probe failed: \(r)"); return }
        #expect(latency >= 0)
        #expect(metrics.count == 4)
        #expect(history > 0)
    }

    /// The real pipeline: endpoint + Keychain key -> DataRefresher -> SwiftData snapshots.
    @Test func endToEndRefreshStoresHistoryAndPicksUpLiveEvents() async throws {
        let ctx = try makeContext()
        let p = Project(name: "Side Shop", accentHex: 0xFF9600, startDate: Date.now.adding(days: -2), buildDays: 14, observeDays: 28)
        p.endpoint = MockServer.url("side-shop").absoluteString
        ctx.insert(p)
        Keychain.set("ss_live_demo", for: p.id.uuidString)
        defer { Keychain.delete(p.id.uuidString) }

        let r = DataRefresher()
        await r.refresh(projects: [p], context: ctx, force: true)
        guard case .live = r.status[p.id] else { Issue.record("status \(String(describing: r.status[p.id]))"); return }
        let firstCount = p.snapshots?.count ?? 0
        #expect(firstCount > 20) // hourly backfill since the project started
        let before = r.latest[p.id]!.value(.revenue)

        try await MockServer.post("side-shop", key: "ss_live_demo", body: #"{"type":"sale","amount":100}"#)
        await r.refresh(projects: [p], context: ctx, force: true)
        let after = r.latest[p.id]!.value(.revenue)
        #expect(after >= before + 100)
        // Second poll only adds what's new (`since`), no duplicates.
        let minutes = (p.snapshots ?? []).map { Int($0.date.timeIntervalSince1970 / 60) }
        #expect(Set(minutes).count == minutes.count)
        #expect((p.snapshots?.count ?? 0) <= firstCount + 1)
    }

    @Test func demoDataMatchesServerProjects() async throws {
        let ctx = try makeContext()
        let profile = Profile()
        profile.remindersEnabled = false
        ctx.insert(profile)
        DemoData.load(baseURL: MockServer.base!, profile: profile, context: ctx)
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projects.count == DemoData.projects.count)
        let r = DataRefresher()
        await r.refresh(projects: projects, context: ctx, force: true)
        for p in projects where p.name != "Flaky App" {
            guard case .live = r.status[p.id] else { Issue.record("\(p.name): \(String(describing: r.status[p.id]))"); continue }
        }
        // Pixel Quest has a generated cover whose color became the accent.
        let pq = try #require(projects.first { $0.name == "Pixel Quest" })
        #expect(pq.coverImage != nil)
        for p in projects { Keychain.delete(p.id.uuidString) }
    }
}
