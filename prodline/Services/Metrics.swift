import Foundation
import Security

// MARK: - Wire format (see docs/API.md)
//
// GET <endpoint>[?since=<ISO8601>]     Authorization: Bearer <api key>
// {
//   "schemaVersion": 1,
//   "project": "My App",
//   "asOf": "2026-10-04T12:00:00Z",
//   "metrics": [ {"key": "visits", "value": 1234}, {"key": "social_views", "value": 560},
//                {"key": "revenue", "value": 56.7, "unit": "USD"}, {"key": "signups", "value": 42} ],
//   "history": [ {"asOf": "...", "metrics": [ ... ]} ]      // optional; points after `since`
// }
// All values are cumulative totals.

nonisolated enum MetricKey: String, CaseIterable, Sendable, Identifiable {
    case visits
    case socialViews = "social_views"
    case revenue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visits: "Visits"
        case .socialViews: "Social views"
        case .revenue: "Revenue"
        }
    }

    var symbol: String {
        switch self {
        case .visits: "globe"
        case .socialViews: "eye.fill"
        case .revenue: "dollarsign.circle.fill"
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .revenue: Self.money(v)
        default: Self.count(v)
        }
    }

    static func money(_ v: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        if v >= 10_000 { return "$" + v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))) }
        return v.formatted(style.precision(.fractionLength(v >= 1000 ? 0 : 2)))
    }

    static func count(_ v: Double) -> String {
        v >= 10_000
            ? v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
            : v.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }
}

nonisolated struct MetricsPayload: Codable, Sendable, Equatable {
    struct Metric: Codable, Sendable, Equatable {
        var key: String
        var value: Double
        var unit: String?
    }
    struct Point: Codable, Sendable, Equatable {
        var asOf: Date
        var metrics: [Metric]
    }
    /// A deliverable the project wants done by a checkpoint.
    struct RemoteGoal: Codable, Sendable, Equatable {
        struct Target: Codable, Sendable, Equatable {
            var key: String
            var target: Double
        }
        var id: String
        var title: String
        var detail: String?
        /// 1-based position in the project's deadline list (checkpoints, launch, review).
        var checkpoint: Int?
        /// Alternative to `checkpoint`: the goal lands on the first deadline on or after this date.
        var due: Date?
        var done: Bool?
        var url: String?
        /// Completes automatically once the metric reaches the target.
        var metric: Target?
    }

    var schemaVersion: Int?
    var project: String?
    var asOf: Date
    var metrics: [Metric]
    var history: [Point]?
    /// Optional. When present, it's the full list: goals missing from it are removed (unless done).
    var goals: [RemoteGoal]?

    func value(_ key: MetricKey) -> Double { metrics.value(key.rawValue) }
    var extras: [String: Double] { metrics.extras }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(s)"))
        }
        return d
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

nonisolated extension Array where Element == MetricsPayload.Metric {
    func value(_ key: String) -> Double { first { $0.key == key }?.value ?? 0 }
    var extras: [String: Double] {
        let core = Set(MetricKey.allCases.map(\.rawValue))
        return Dictionary(filter { !core.contains($0.key) }.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
    }
}

nonisolated extension MetricsPayload.Point {
    func value(_ key: MetricKey) -> Double { metrics.value(key.rawValue) }
}

// MARK: - Errors

nonisolated enum MetricsError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case unauthorized
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    case badPayload(String)
    case offline(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The endpoint URL isn't valid."
        case .unauthorized: "The API key was rejected (401)."
        case .notFound: "Endpoint not found (404). Check the URL."
        case .rateLimited: "Too many requests. Backing off."
        case .server(let code): "The project's server answered \(code)."
        case .badPayload(let why): "Unexpected response: \(why)"
        case .offline(let why): why
        }
    }

    var retryAfter: TimeInterval? {
        if case .rateLimited(let t) = self { return t }
        return nil
    }
}

// MARK: - Clients

nonisolated protocol MetricsClient: Sendable {
    /// `since`: the newest point the app already has; servers may limit `history` to newer points.
    func fetch(since: Date?) async throws -> MetricsPayload
}

nonisolated struct RESTMetricsClient: MetricsClient {
    let url: URL
    let apiKey: String
    var session: URLSession = .shared

    func fetch(since: Date?) async throws -> MetricsPayload {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MetricsError.invalidURL }
        if let since {
            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "since", value: MetricsPayload.iso(since))]
        }
        guard let finalURL = comps.url else { throw MetricsError.invalidURL }

        var req = URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Prodline/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            throw MetricsError.offline(e.code == .notConnectedToInternet ? "You're offline." : "Can't reach the server (\(e.code.rawValue)).")
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw MetricsError.unauthorized
            case 404: throw MetricsError.notFound
            case 429: throw MetricsError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
            default: throw MetricsError.server(http.statusCode)
            }
        }

        do {
            return try MetricsPayload.decoder().decode(MetricsPayload.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw MetricsError.badPayload("missing \"\(key.stringValue)\"")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw MetricsError.badPayload("wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw MetricsError.badPayload(ctx.debugDescription)
        } catch {
            throw MetricsError.badPayload("not valid JSON")
        }
    }
}

/// Deterministic, slowly growing fake numbers so the app is usable before a project is connected.
nonisolated struct SampleMetricsClient: MetricsClient {
    let seed: Int
    let start: Date

    func values(at date: Date) -> (Double, Double, Double) {
        let days = max(0, date.timeIntervalSince(start) / 86_400)
        let s = Double(abs(seed) % 53 + 20)
        let visits = s * 6 * pow(days + 0.5, 1.25) + days * s
        let social = visits * 0.55 + s * 12 * days
        let revenue = visits * (0.004 + Double(abs(seed) % 5) * 0.002)
        return (visits.rounded(), social.rounded(), (revenue * 100).rounded() / 100)
    }

    private func metrics(_ v: (Double, Double, Double)) -> [MetricsPayload.Metric] {
        [.init(key: "visits", value: v.0), .init(key: "social_views", value: v.1), .init(key: "revenue", value: v.2, unit: "USD")]
    }

    func fetch(since: Date?) async throws -> MetricsPayload {
        try? await Task.sleep(for: .milliseconds(250))
        let now = Date()
        var history: [MetricsPayload.Point] = []
        for back in stride(from: 14, through: 1, by: -1) {
            let d = Calendar.current.startOfDay(for: now).addingTimeInterval(-Double(back) * 86_400)
            if d >= start, since.map({ d > $0 }) ?? true { history.append(.init(asOf: d, metrics: metrics(values(at: d)))) }
        }
        return MetricsPayload(schemaVersion: 1, project: nil, asOf: now, metrics: metrics(values(at: now)), history: history, goals: nil)
    }
}

nonisolated extension MetricsPayload.Metric {
    init(key: String, value: Double) { self.init(key: key, value: value, unit: nil) }
}

// MARK: - Keychain (API keys never touch SwiftData / iCloud records)

enum Keychain {
    private static let service = "expbsn.app.prodline"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        guard !value.isEmpty else { return }
        var q = base(account)
        q[kSecAttrSynchronizable as String] = true // iCloud Keychain
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock // background refresh
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }
}
