import Foundation
import Testing
@testable import prodline

@Suite("Web integrations")
struct WebIntegrationTests {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [WebStub.self]
        return URLSession(configuration: cfg)
    }

    @Test func shopifyCountsPaidOrdersMinusRefundsAndSkipsCancelled() async throws {
        let i = Integration(kind: .shopify, fields: ["shop": "https://kite-shop.myshopify.com/"])
        let r = try await IntegrationSources.shopify(i, secret: "shpat_test", start: day(2026, 10, 1), session: session())
        #expect(WebStub.lastHost == "kite-shop.myshopify.com")
        #expect(WebStub.lastToken == "shpat_test")
        #expect(r.totals["sales"] == 2)
        #expect(r.totals["revenue"] == 45)
    }

    @Test func npmNeedsNoKeyAndKeepsDailyHistory() async throws {
        let i = Integration(kind: .npm, fields: ["package": "left-pad"])
        let r = try await IntegrationSources.fetch(i, secret: "", start: day(2026, 10, 1), session: session(), cache: IntegrationCache())
        #expect(r.totals["downloads"] == 30)
        #expect(r.daily[DayKey.string(day(2026, 10, 2))]?["downloads"] == 20)
    }

    @Test func netlifyCountsReadyDeploysSinceTheStart() async throws {
        let i = Integration(kind: .netlify, fields: ["site": "abc"])
        let r = try await IntegrationSources.netlify(i, secret: "nf", start: day(2026, 10, 1), session: session())
        #expect(r.totals["deploys"] == 2)
    }

    @Test func hackerNewsSumsPoints() async throws {
        let i = Integration(kind: .hackerNews, fields: ["url": "https://kite.app"])
        let r = try await IntegrationSources.hackerNews(i, start: day(2026, 10, 1), session: session())
        #expect(r.totals["hn_points"] == 140)
        #expect(WebStub.lastQuery?.contains("kite.app") == true)
    }

    @Test func keyedSourcesStillNeedAKey() async {
        let i = Integration(kind: .vercel, fields: ["projectID": "prj"])
        await #expect(throws: MetricsError.self) {
            try await IntegrationSources.fetch(i, secret: "", start: day(2026, 10, 1), session: session(), cache: IntegrationCache())
        }
    }
}

/// Shopify, npm, Netlify and Hacker News answered locally.
final class WebStub: URLProtocol {
    nonisolated(unsafe) static var lastHost: String?
    nonisolated(unsafe) static var lastToken: String?
    nonisolated(unsafe) static var lastQuery: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        var body = "{}"
        switch url.host() ?? "" {
        case let h where h.hasSuffix("myshopify.com"):
            Self.lastHost = h
            Self.lastToken = request.value(forHTTPHeaderField: "X-Shopify-Access-Token")
            body = #"""
            {"data":{"orders":{"edges":[
              {"node":{"createdAt":"2026-10-02T10:00:00Z","cancelledAt":null,"displayFinancialStatus":"PAID","totalPriceSet":{"shopMoney":{"amount":"30.00","currencyCode":"USD"}},"totalRefundedSet":{"shopMoney":{"amount":"0.00"}}}},
              {"node":{"createdAt":"2026-10-03T10:00:00Z","cancelledAt":null,"displayFinancialStatus":"PARTIALLY_REFUNDED","totalPriceSet":{"shopMoney":{"amount":"20.00","currencyCode":"USD"}},"totalRefundedSet":{"shopMoney":{"amount":"5.00"}}}},
              {"node":{"createdAt":"2026-10-03T11:00:00Z","cancelledAt":"2026-10-03T12:00:00Z","displayFinancialStatus":"PAID","totalPriceSet":{"shopMoney":{"amount":"99.00","currencyCode":"USD"}},"totalRefundedSet":{"shopMoney":{"amount":"0.00"}}}},
              {"node":{"createdAt":"2026-10-04T10:00:00Z","cancelledAt":null,"displayFinancialStatus":"PENDING","totalPriceSet":{"shopMoney":{"amount":"50.00","currencyCode":"USD"}},"totalRefundedSet":{"shopMoney":{"amount":"0.00"}}}}
            ],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}
            """#
        case "api.npmjs.org":
            body = #"{"downloads":[{"day":"2026-10-01","downloads":10},{"day":"2026-10-02","downloads":20}],"package":"left-pad"}"#
        case "api.netlify.com":
            body = #"""
            [{"created_at":"2026-10-04T10:00:00Z","state":"ready"},{"created_at":"2026-10-03T10:00:00Z","state":"error"},
             {"created_at":"2026-10-02T10:00:00Z","state":"ready"},{"created_at":"2026-09-20T10:00:00Z","state":"ready"}]
            """#
        case "hn.algolia.com":
            Self.lastQuery = url.query()
            body = #"{"hits":[{"points":120,"num_comments":40},{"points":20,"num_comments":3}]}"#
        default: break
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
