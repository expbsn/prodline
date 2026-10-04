import Foundation
import Security

// MARK: - Wire format
//
// GET <endpoint>   Authorization: Bearer <api key>
// {
//   "project": "My App",
//   "asOf": "2026-10-04T12:00:00Z",
//   "metrics": [ {"key": "visits", "value": 1234}, {"key": "social_views", "value": 560},
//                {"key": "revenue", "value": 56.7, "unit": "USD"} ],
//   "history": [ {"asOf": "...", "metrics": [ ... ]} ]      // optional, for backfilling charts
// }

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

    var icon: String {
        switch self {
        case .visits: "🌐"
        case .socialViews: "👀"
        case .revenue: "💰"
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .revenue:
            return v.formatted(.currency(code: "USD").precision(.fractionLength(v >= 1000 ? 0 : 2)))
        default:
            return v >= 10_000 ? v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
                               : v.formatted(.number.precision(.fractionLength(0)))
        }
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

    var project: String?
    var asOf: Date
    var metrics: [Metric]
    var history: [Point]?

    func value(_ key: MetricKey) -> Double {
        metrics.first { $0.key == key.rawValue }?.value ?? 0
    }
}

nonisolated extension MetricsPayload.Point {
    func value(_ key: MetricKey) -> Double { metrics.first { $0.key == key.rawValue }?.value ?? 0 }
}

// MARK: - Clients

nonisolated protocol MetricsClient: Sendable {
    func fetch() async throws -> MetricsPayload
}

nonisolated struct RESTMetricsClient: MetricsClient {
    let url: URL
    let apiKey: String

    enum ClientError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(401), .http(403): "The API key was rejected."
            case .http(let c): "Server answered with \(c)."
            }
        }
    }

    func fetch() async throws -> MetricsPayload {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Bad date \(s)"))
        }
        return try decoder.decode(MetricsPayload.self, from: data)
    }
}

/// Deterministic, slowly growing fake numbers so the app is fully usable before a project is connected.
nonisolated struct MockMetricsClient: MetricsClient {
    let seed: Int
    let start: Date

    private func values(at date: Date) -> (Double, Double, Double) {
        let days = max(0, date.timeIntervalSince(start) / 86_400)
        let s = Double(abs(seed) % 53 + 20)
        let visits = s * 6 * pow(days + 0.5, 1.25) + days * s
        let social = visits * 0.55 + s * 12 * days
        let revenue = visits * (0.004 + Double(abs(seed) % 5) * 0.002)
        return (visits.rounded(), social.rounded(), (revenue * 100).rounded() / 100)
    }

    private func metrics(_ v: (Double, Double, Double)) -> [MetricsPayload.Metric] {
        [.init(key: "visits", value: v.0, unit: nil),
         .init(key: "social_views", value: v.1, unit: nil),
         .init(key: "revenue", value: v.2, unit: "USD")]
    }

    func fetch() async throws -> MetricsPayload {
        try? await Task.sleep(for: .milliseconds(350))
        let now = Date()
        var history: [MetricsPayload.Point] = []
        for back in stride(from: 14, through: 1, by: -1) {
            let d = Calendar.current.startOfDay(for: now).addingTimeInterval(-Double(back) * 86_400)
            if d >= start { history.append(.init(asOf: d, metrics: metrics(values(at: d)))) }
        }
        return MetricsPayload(project: nil, asOf: now, metrics: metrics(values(at: now)), history: history)
    }
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
