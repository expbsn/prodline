import Foundation
import CryptoKit
import Compression
import Testing
@testable import prodline

@Suite("Integrations")
struct IntegrationTests {
    @Test func appStoreProceedsDontDoubleCountWithRevenueCat() {
        let start = day(2026, 10, 1)
        let now = day(2026, 10, 4).addingTimeInterval(12 * 3600)
        let asc = IntegrationSources.summed([(day(2026, 10, 2), ["downloads": 40, "revenue": 12])], start: start, keys: ["downloads", "revenue"])
        let rc = IntegrationSources.summed([(day(2026, 10, 2), ["revenue": 30])], start: start, keys: ["revenue"])
        let plausible = IntegrationSources.summed([(day(2026, 10, 1), ["visits": 100]), (day(2026, 10, 3), ["visits": 50])],
                                                  start: start, keys: ["visits"])

        let both = IntegrationsClient.combine([(.appStore, asc), (.revenueCat, rc), (.plausible, plausible)], endpoint: nil, start: start, now: now)
        #expect(both.metrics.value("revenue") == 30)
        #expect(both.metrics.value("downloads") == 40)
        #expect(both.metrics.value("visits") == 150)
        // Oct 1–3 are finished days; Oct 4 is today.
        #expect(both.history?.count == 3)
        #expect(both.history?.last?.metrics.value("visits") == 150)
        #expect(both.history?[1].metrics.value("revenue") == 30)

        let alone = IntegrationsClient.combine([(.appStore, asc)], endpoint: nil, start: start, now: now)
        #expect(alone.metrics.value("revenue") == 12)
    }

    @Test func historyStopsWhereASourceHasNoDataYet() {
        let start = day(2026, 10, 1)
        let now = day(2026, 10, 5)
        var partial = SourceResult()
        partial.totals = ["downloads": 5]
        partial.daily = [DayKey.string(day(2026, 10, 1)): ["downloads": 2], DayKey.string(day(2026, 10, 2)): ["downloads": 3]]
        partial.dailyKeys = ["downloads"]
        let full = IntegrationSources.summed([], start: start, keys: ["visits"])
        let p = IntegrationsClient.combine([(.appStore, partial), (.plausible, full)], endpoint: nil, start: start, now: now)
        #expect(p.history?.count == 2)
    }

    @Test func endpointFillsKeysTheIntegrationsDontHave() {
        let start = day(2026, 10, 1)
        let stripe = IntegrationSources.summed([(day(2026, 10, 1), ["revenue": 9, "sales": 1])], start: start, keys: ["revenue", "sales"])
        let endpoint = MetricsPayload(schemaVersion: 1, project: nil, asOf: day(2026, 10, 2),
                                      metrics: [.init(key: "revenue", value: 999), .init(key: "signups", value: 7)], history: nil, goals: nil)
        let p = IntegrationsClient.combine([(.stripe, stripe)], endpoint: endpoint, start: start, now: day(2026, 10, 2))
        #expect(p.metrics.value("revenue") == 9)
        #expect(p.metrics.value("signups") == 7)
    }

    @Test func salesReportCountsFirstDownloadsAndPurchases() {
        let header = ["Provider", "Provider Country", "SKU", "Developer", "Title", "Version", "Product Type Identifier", "Units",
                      "Developer Proceeds", "Begin Date", "End Date", "Customer Currency", "Country Code", "Currency of Proceeds",
                      "Apple Identifier", "Customer Price", "Promo Code", "Parent Identifier"]
        func row(_ sku: String, _ type: String, _ units: String, _ proceeds: String, _ cur: String, _ apple: String, parent: String = "") -> String {
            ["APPLE", "US", sku, "Me", "T", "1", type, units, proceeds, "", "", cur, "US", cur, apple, "0", "", parent].joined(separator: "\t")
        }
        let tsv = ([header.joined(separator: "\t"),
                    row("habit", "1F", "12", "0", "USD", "111"),
                    row("habit", "7F", "30", "0", "USD", "111"),          // updates don't count
                    row("habit", "3F", "4", "0", "USD", "111"),           // redownloads don't count
                    row("pro", "IA1", "2", "6.99", "EUR", "222", parent: "habit"),
                    row("other", "1F", "99", "0", "USD", "333")]).joined(separator: "\n")
        let r = IntegrationSources.parseSalesReport(tsv, appID: "111")
        #expect(r.downloads == 12)
        #expect(r.proceeds.count == 1)
        #expect(r.proceeds.first?.0 == 13.98)
        #expect(r.proceeds.first?.1 == "EUR")
    }

    @Test func gzipRoundTrip() throws {
        let text = String(repeating: "Provider\tUnits\n", count: 200)
        let raw = [UInt8](text.utf8)
        var deflated = [UInt8](repeating: 0, count: raw.count + 64)
        let n = compression_encode_buffer(&deflated, deflated.count, raw, raw.count, nil, COMPRESSION_ZLIB)
        #expect(n > 0)
        let size = UInt32(raw.count)
        var gz: [UInt8] = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3] + deflated[0..<n] + [0, 0, 0, 0]
        gz += [UInt8(size & 0xff), UInt8(size >> 8 & 0xff), UInt8(size >> 16 & 0xff), UInt8(size >> 24 & 0xff)]
        let out = try #require(Gzip.inflate(Data(gz)))
        #expect(String(decoding: out, as: UTF8.self) == text)
        #expect(Gzip.inflate(Data(raw)) == nil)
    }

    @Test func appStoreTokenIsAValidES256JWT() throws {
        let key = P256.Signing.PrivateKey()
        let token = try IntegrationSources.appStoreToken(issuer: "issuer-1", keyID: "KEY123", pem: key.pemRepresentation,
                                                         now: Date(timeIntervalSince1970: 1_800_000_000))
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        func data(_ s: String) -> Data {
            var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            return Data(base64Encoded: b)!
        }
        let header = try JSONSerialization.jsonObject(with: data(parts[0])) as? [String: Any]
        let payload = try JSONSerialization.jsonObject(with: data(parts[1])) as? [String: Any]
        #expect(header?["alg"] as? String == "ES256")
        #expect(header?["kid"] as? String == "KEY123")
        #expect(payload?["iss"] as? String == "issuer-1")
        #expect(payload?["aud"] as? String == "appstoreconnect-v1")
        #expect((payload?["exp"] as? Int).map { $0 - 1_800_000_000 } == 900)
        let sig = try P256.Signing.ECDSASignature(rawRepresentation: data(parts[2]))
        #expect(key.publicKey.isValidSignature(sig, for: Data((parts[0] + "." + parts[1]).utf8)))
        #expect(throws: MetricsError.self) { try IntegrationSources.appStoreToken(issuer: "i", keyID: "k", pem: "nope") }
    }

    @Test func stripeSumsChargesMinusRefunds() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StripeStub.self]
        let r = try await IntegrationSources.stripe(secret: "rk_test", start: day(2026, 10, 1), session: URLSession(configuration: cfg))
        #expect(StripeStub.lastAuth == "Bearer rk_test")
        #expect(r.totals["revenue"] == 10)
        #expect(r.totals["sales"] == 1)
        #expect(r.daily[DayKey.string(day(2026, 10, 3))]?["revenue"] == -9.99)
    }
}

/// Stripe's balance transactions, answered locally (its own class, so suites using StubProtocol can run alongside).
final class StripeStub: URLProtocol {
    nonisolated(unsafe) static var lastAuth: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lastAuth = request.value(forHTTPHeaderField: "Authorization")
        let t = { (d: Date, h: Double) in Int(d.timeIntervalSince1970 + h * 3600) }
        let body = """
        {"has_more": false, "data": [
          {"id": "txn_1", "type": "charge", "amount": 1999, "currency": "usd", "created": \(t(day(2026, 10, 2), 1))},
          {"id": "txn_2", "type": "refund", "amount": -999, "currency": "usd", "created": \(t(day(2026, 10, 3), 1))},
          {"id": "txn_3", "type": "payout", "amount": -5000, "currency": "usd", "created": \(t(day(2026, 10, 3), 2))}
        ]}
        """
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("YouTube")
struct YouTubeTests {
    @Test func countsViewsOnVideosSinceTheStart() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [YouTubeStub.self]
        let i = Integration(kind: .youtube, fields: ["channel": "@prodline"])
        let r = try await IntegrationSources.youtube(i, secret: "AIzaTest", start: day(2026, 10, 1), session: URLSession(configuration: cfg))
        #expect(r.totals["social_views"] == 1500)
        #expect(r.totals["videos_posted"] == 2)
        #expect(r.totals["subscribers"] == 321)
        #expect(YouTubeStub.sawHandle)
    }
}

/// Channel → uploads (two new videos, then one from before the start) → video stats.
final class YouTubeStub: URLProtocol {
    nonisolated(unsafe) static var sawHandle = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func has(_ name: String, _ value: String) -> Bool { q.contains { $0.name == name && $0.value == value } }
        var body = "{}"
        if url.path.hasSuffix("/channels") {
            Self.sawHandle = has("forHandle", "@prodline") && has("key", "AIzaTest")
            body = #"{"items":[{"statistics":{"subscriberCount":"321","viewCount":"99999"},"contentDetails":{"relatedPlaylists":{"uploads":"UUx"}}}]}"#
        } else if url.path.hasSuffix("/playlistItems") {
            body = #"{"items":[{"contentDetails":{"videoId":"a","videoPublishedAt":"2026-10-05T10:00:00Z"}},{"contentDetails":{"videoId":"b","videoPublishedAt":"2026-10-02T10:00:00Z"}},{"contentDetails":{"videoId":"old","videoPublishedAt":"2026-09-20T10:00:00Z"}}],"nextPageToken":"p2"}"#
        } else if url.path.hasSuffix("/videos") {
            body = has("id", "a,b") ? #"{"items":[{"statistics":{"viewCount":"1000"}},{"statistics":{"viewCount":"500"}}]}"# : #"{"items":[]}"#
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
