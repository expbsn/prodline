import Foundation
import SwiftData
@testable import prodline

@MainActor
func makeContext() throws -> ModelContext {
    let container = try ModelContainer(for: Profile.self, Project.self, Milestone.self, MetricSnapshot.self, Goal.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

/// A local-calendar date at midnight.
func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
}

func payload(asOf: Date, visits: Double, social: Double = 0, revenue: Double = 0,
             extras: [String: Double] = [:], history: [MetricsPayload.Point]? = nil,
             goals: [MetricsPayload.RemoteGoal]? = nil) -> MetricsPayload {
    var metrics: [MetricsPayload.Metric] = [
        .init(key: "visits", value: visits),
        .init(key: "social_views", value: social),
        .init(key: "revenue", value: revenue, unit: "USD"),
    ]
    metrics += extras.map { .init(key: $0.key, value: $0.value) }
    return MetricsPayload(schemaVersion: 1, project: "Test", asOf: asOf, metrics: metrics, history: history, goals: goals)
}

/// Scriptable client that counts calls.
final class FakeClient: MetricsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _sinceSeen: [Date?] = []
    var responder: @Sendable (Int) throws -> MetricsPayload

    init(_ responder: @escaping @Sendable (Int) throws -> MetricsPayload) { self.responder = responder }

    var calls: Int { lock.withLock { _calls } }
    var sinceSeen: [Date?] { lock.withLock { _sinceSeen } }

    func fetch(since: Date?) async throws -> MetricsPayload {
        let n: Int = lock.withLock { _calls += 1; _sinceSeen.append(since); return _calls }
        return try responder(n)
    }
}

/// Routes URLSession requests to a closure.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let h = Self.handler else { return }
        let (code, headers, data) = h(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var session: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: cfg)
    }
}
