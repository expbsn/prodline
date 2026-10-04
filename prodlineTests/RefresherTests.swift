import Foundation
import SwiftData
import Testing
@testable import prodline

@MainActor
@Suite("Data refresher")
struct RefresherTests {
    let now = Date.now

    private func setup(phaseStart: Int = -3) throws -> (ModelContext, Project) {
        let ctx = try makeContext()
        let p = Project(name: "P", accentHex: 0x58CC02, startDate: Date.now.adding(days: phaseStart), buildDays: 14, observeDays: 28)
        ctx.insert(p)
        return (ctx, p)
    }

    private func refresher(_ client: FakeClient, sample: Bool = false) -> DataRefresher {
        DataRefresher { _ in (client, sample) }
    }

    @Test func backfillsHistoryOnceAndStoresLivePoint() async throws {
        let (ctx, p) = try setup()
        let history = (1...3).map { h in
            MetricsPayload.Point(asOf: now.addingTimeInterval(-Double(h) * 3600),
                                 metrics: [.init(key: "visits", value: Double(100 - h))])
        }
        let client = FakeClient { _ in payload(asOf: self.now, visits: 120, extras: ["signups": 7], history: history) }
        let r = refresher(client)

        await r.refresh(projects: [p], context: ctx, force: true, now: now)
        #expect(p.snapshots?.count == 4)
        #expect(p.latestSnapshot?.visits == 120)
        #expect(p.latestSnapshot?.extras == ["signups": 7])
        #expect(r.status[p.id] == .live(now))

        // Same data again: nothing duplicated, and `since` is the newest stored point.
        await r.refresh(projects: [p], context: ctx, force: true, now: now)
        #expect(p.snapshots?.count == 4)
        #expect(client.sinceSeen.last == .some(now))
    }

    @Test func throttlesStoredLivePoints() async throws {
        let (ctx, p) = try setup()
        let client = FakeClient { n in payload(asOf: self.now.addingTimeInterval(Double(n - 1) * 5 * 60), visits: Double(n)) }
        let r = refresher(client)
        // Polls 5 minutes apart: only every third (15 min) is persisted, but `latest` always updates.
        for i in 0..<7 {
            await r.refresh(projects: [p], context: ctx, force: true, now: now.addingTimeInterval(Double(i) * 300))
        }
        #expect(client.calls == 7)
        #expect(p.snapshots?.count == 3) // t = 0, 15, 30 min
        #expect(r.latest[p.id]?.value(.visits) == 7)
    }

    @Test func backsOffExponentiallyAndRecovers() async throws {
        let (ctx, p) = try setup()
        let client = FakeClient { n in
            if n <= 2 { throw MetricsError.server(503) }
            return payload(asOf: self.now, visits: 1)
        }
        let r = refresher(client)

        await r.refresh(projects: [p], context: ctx, now: now)
        #expect(client.calls == 1)
        guard case .failing(_, let retry1) = r.status[p.id] else { Issue.record("expected failing"); return }
        #expect(retry1 == now.addingTimeInterval(30))

        // Within the backoff window the project is skipped.
        await r.refresh(projects: [p], context: ctx, now: now.addingTimeInterval(15))
        #expect(client.calls == 1)

        await r.refresh(projects: [p], context: ctx, now: now.addingTimeInterval(31))
        #expect(client.calls == 2)
        guard case .failing(_, let retry2) = r.status[p.id] else { Issue.record("expected failing"); return }
        #expect(retry2 == now.addingTimeInterval(31 + 60)) // doubled

        await r.refresh(projects: [p], context: ctx, now: now.addingTimeInterval(100))
        #expect(client.calls == 3)
        #expect(r.failures[p.id] == 0)
        #expect(r.status[p.id] == .live(now.addingTimeInterval(100)))
    }

    @Test func backoffIsCapped() async throws {
        let (ctx, p) = try setup()
        let client = FakeClient { _ in throw MetricsError.server(500) }
        let r = refresher(client)
        var t = now
        for _ in 0..<12 {
            await r.refresh(projects: [p], context: ctx, force: true, now: t)
            t = t.addingTimeInterval(DataRefresher.maxBackoff + 1)
        }
        guard case .failing(_, let retry) = r.status[p.id] else { Issue.record("expected failing"); return }
        #expect(retry.timeIntervalSince(t.addingTimeInterval(-(DataRefresher.maxBackoff + 1))) == DataRefresher.maxBackoff)
    }

    @Test func honorsRetryAfter() async throws {
        let (ctx, p) = try setup()
        let client = FakeClient { _ in throw MetricsError.rateLimited(retryAfter: 120) }
        let r = refresher(client)
        await r.refresh(projects: [p], context: ctx, now: now)
        guard case .failing(_, let retry) = r.status[p.id] else { Issue.record("expected failing"); return }
        #expect(retry == now.addingTimeInterval(120))
    }

    @Test func skipsInactiveProjectsAndRespectsMinGap() async throws {
        let ctx = try makeContext()
        let upcoming = Project(name: "U", accentHex: 0, startDate: Date.now.adding(days: 5), buildDays: 14, observeDays: 28)
        let finished = Project(name: "F", accentHex: 0, startDate: Date.now.adding(days: -100), buildDays: 14, observeDays: 28)
        let active = Project(name: "A", accentHex: 0, startDate: Date.now.adding(days: -20), buildDays: 14, observeDays: 28)
        [upcoming, finished, active].forEach(ctx.insert)
        let client = FakeClient { _ in payload(asOf: self.now, visits: 1) }
        let r = refresher(client)

        await r.refresh(projects: [upcoming, finished, active], context: ctx, now: now)
        #expect(client.calls == 1) // only the observing project
        await r.refresh(projects: [active], context: ctx, now: now.addingTimeInterval(5))
        #expect(client.calls == 1) // within minGap
        await r.refresh(projects: [active], context: ctx, now: now.addingTimeInterval(11))
        #expect(client.calls == 2)
    }

    @Test func sampleClientIsMarkedAsSample() async throws {
        let (ctx, p) = try setup()
        let r = DataRefresher { proj in (SampleMetricsClient(seed: 7, start: proj.startDate), true) }
        await r.refresh(projects: [p], context: ctx, force: true)
        #expect(r.status[p.id] == .sample)
        #expect((p.snapshots?.count ?? 0) >= 3) // sample history backfills daily points
    }

    @Test func defaultClientNeedsEndpointAndKey() throws {
        let (_, p) = try setup()
        #expect(DataRefresher.defaultClient(for: p).isSample)
        p.endpoint = "https://example.com/m"
        #expect(DataRefresher.defaultClient(for: p).isSample) // no key yet
        Keychain.set("k", for: p.id.uuidString)
        defer { Keychain.delete(p.id.uuidString) }
        #expect(!DataRefresher.defaultClient(for: p).isSample)
        p.endpoint = "not a url"
        #expect(DataRefresher.defaultClient(for: p).isSample)
    }
}
