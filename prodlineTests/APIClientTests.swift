import Foundation
import Testing
@testable import prodline

@Suite("Payload decoding")
struct PayloadTests {
    @Test func decodesFullPayloadWithFractionalAndPlainDates() throws {
        let json = """
        {
          "schemaVersion": 1, "project": "X", "asOf": "2026-10-04T12:00:00.250Z",
          "metrics": [
            {"key": "visits", "value": 1234}, {"key": "social_views", "value": 560},
            {"key": "revenue", "value": 56.7, "unit": "USD"}, {"key": "signups", "value": 42}
          ],
          "history": [{"asOf": "2026-10-04T11:00:00Z", "metrics": [{"key": "visits", "value": 1100}]}]
        }
        """
        let p = try MetricsPayload.decoder().decode(MetricsPayload.self, from: Data(json.utf8))
        #expect(p.value(.visits) == 1234)
        #expect(p.value(.socialViews) == 560)
        #expect(p.value(.revenue) == 56.7)
        #expect(p.extras == ["signups": 42])
        #expect(p.history?.count == 1)
        #expect(p.history?.first?.value(.visits) == 1100)
        #expect(p.history?.first?.value(.revenue) == 0) // missing => 0
    }

    @Test func historyAndSchemaVersionAreOptional() throws {
        let json = #"{"asOf":"2026-10-04T12:00:00Z","metrics":[{"key":"visits","value":1}]}"#
        let p = try MetricsPayload.decoder().decode(MetricsPayload.self, from: Data(json.utf8))
        #expect(p.history == nil)
        #expect(p.schemaVersion == nil)
        #expect(p.extras.isEmpty)
    }

    @Test func rejectsBadDates() {
        let json = #"{"asOf":"yesterday","metrics":[]}"#
        #expect(throws: DecodingError.self) {
            try MetricsPayload.decoder().decode(MetricsPayload.self, from: Data(json.utf8))
        }
    }

    @Test func formatting() {
        #expect(MetricKey.money(56.7) == "$56.70")
        #expect(MetricKey.money(1234) == "$1,234")
        #expect(MetricKey.money(25_300).hasPrefix("$25"))
        #expect(MetricKey.count(999) == "999")
        #expect(MetricKey.count(12_345) == "12.3K")
    }
}

@Suite("REST client", .serialized)
struct RESTClientTests {
    let url = URL(string: "https://example.com/api/prodline")!

    private func client() -> RESTMetricsClient {
        RESTMetricsClient(url: url, apiKey: "secret", session: StubProtocol.session)
    }

    @Test func sendsBearerKeyAndSince() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        StubProtocol.handler = { req in
            seen = req
            return (200, [:], Data(#"{"asOf":"2026-10-04T12:00:00Z","metrics":[{"key":"visits","value":5}]}"#.utf8))
        }
        let since = Date(timeIntervalSince1970: 1_790_000_000)
        let p = try await client().fetch(since: since)
        #expect(p.value(.visits) == 5)
        #expect(seen?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let q = URLComponents(url: seen!.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(q?.first { $0.name == "since" }.flatMap { $0.value.flatMap(MetricsPayload.parseDate) } == since)
    }

    @Test(arguments: [
        (401, MetricsError.unauthorized),
        (403, MetricsError.unauthorized),
        (404, MetricsError.notFound),
        (500, MetricsError.server(500)),
        (503, MetricsError.server(503)),
    ])
    func mapsStatusCodes(code: Int, expected: MetricsError) async {
        StubProtocol.handler = { _ in (code, [:], Data("{}".utf8)) }
        await #expect(throws: expected) { try await client().fetch(since: nil) }
    }

    @Test func rateLimitHonorsRetryAfter() async {
        StubProtocol.handler = { _ in (429, ["Retry-After": "120"], Data()) }
        await #expect(throws: MetricsError.rateLimited(retryAfter: 120)) { try await client().fetch(since: nil) }
    }

    @Test func malformedBodyIsBadPayload() async {
        StubProtocol.handler = { _ in (200, [:], Data("{not json".utf8)) }
        do {
            _ = try await client().fetch(since: nil)
            Issue.record("expected failure")
        } catch let e as MetricsError {
            if case .badPayload = e {} else { Issue.record("wrong error \(e)") }
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func missingFieldNamesTheField() async {
        StubProtocol.handler = { _ in (200, [:], Data(#"{"metrics":[]}"#.utf8)) }
        await #expect(throws: MetricsError.badPayload("missing \"asOf\"")) { try await client().fetch(since: nil) }
    }
}
