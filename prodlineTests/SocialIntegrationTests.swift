import Foundation
import Testing
@testable import prodline

/// Answers requests from a table (URL substring → JSON) instead of the network.
final class SocialStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [(String, String)] = []
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen.append(request)
        let url = request.url?.absoluteString ?? ""
        let body = Self.answers.first { url.contains($0.0) }?.1 ?? "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SocialStub.self]
        return URLSession(configuration: c)
    }
}

@Suite("Social integrations", .serialized)
struct SocialIntegrationTests {
    @Test func tokenBundleRoundTrips() {
        let t = SocialTokens(access: "a", refresh: "r", expires: 100, refreshExpires: 200, user: "u")
        #expect(SocialTokens(t.json) == t)
        #expect(SocialTokens("sk_live_not_json") == nil)
    }

    @Test func tiktokCountsVideosSinceTheStart() async throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let fresh = Date().timeIntervalSince1970 + 86400
        SocialStub.seen = []
        SocialStub.answers = [
            ("video/list", """
             {"data": {"videos": [{"id": "1", "create_time": 1790100000, "view_count": 1200},
                                  {"id": "2", "create_time": 1790050000, "view_count": 300},
                                  {"id": "3", "create_time": 1789000000, "view_count": 99999}],
                       "cursor": 1789000000, "has_more": true}, "error": {"code": "ok"}}
             """),
            ("user/info", #"{"data": {"user": {"follower_count": 512}}, "error": {"code": "ok"}}"#),
        ]
        let i = Integration(kind: .tiktok)
        let secret = SocialTokens(access: "tok", refresh: "r", expires: fresh, refreshExpires: nil, user: "u").json
        let r = try await IntegrationSources.tiktok(i, secret: secret, start: start, session: SocialStub.session())
        #expect(r.totals["social_views"] == 1500)
        #expect(r.totals["videos_posted"] == 2)
        #expect(r.totals["followers"] == 512)
        // Stopped at the older video instead of asking for the next page; the token wasn't renewed.
        #expect(SocialStub.seen.filter { $0.url?.path.contains("video/list") == true }.count == 1)
        #expect(SocialStub.seen.allSatisfy { $0.url?.path.contains("oauth") != true })
    }

    @Test func tiktokInvalidTokenAsksToSignInAgain() async {
        SocialStub.answers = [("video/list", #"{"data": {}, "error": {"code": "access_token_invalid"}}"#)]
        let secret = SocialTokens(access: "tok", refresh: "r", expires: Date().timeIntervalSince1970 + 86400, refreshExpires: nil, user: "u").json
        await #expect(throws: MetricsError.signInExpired) {
            _ = try await IntegrationSources.tiktok(Integration(kind: .tiktok), secret: secret, start: .now, session: SocialStub.session())
        }
    }
}
