import Foundation
import CryptoKit
import AuthenticationServices
import UIKit

// MARK: - TikTok, Instagram and Threads
//
// These only give tokens to a server that knows the app secret, so sign-in goes through the relay
// (relay/src/index.js, "Social sign-in"): the app opens /oauth/<provider>/start in a web sheet, the
// relay swaps the code for tokens and sends the sheet back to prodline://oauth/<provider>, and the app
// collects the tokens once with a verifier only it knows. The tokens are the integration's Keychain
// secret, as JSON; fetches renew them when they're close to running out and write them back.

nonisolated struct SocialTokens: Codable, Sendable, Equatable {
    var access: String
    var refresh: String?
    /// Seconds since 1970.
    var expires: Double
    var refreshExpires: Double?
    var user: String

    init?(_ secret: String) {
        guard let t = try? JSONDecoder().decode(SocialTokens.self, from: Data(secret.utf8)) else { return nil }
        self = t
    }

    init(access: String, refresh: String?, expires: Double, refreshExpires: Double?, user: String) {
        self.access = access; self.refresh = refresh; self.expires = expires; self.refreshExpires = refreshExpires; self.user = user
    }

    var json: String { (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

nonisolated enum SocialSignIn {
    enum Failure: LocalizedError {
        case cancelled, denied, failed, notSetUp
        var errorDescription: String? {
            switch self {
            case .cancelled: nil
            case .denied: "Sign-in was declined."
            case .failed: "Sign-in didn't go through. Try again."
            case .notSetUp: "This sign-in isn't available yet."
            }
        }
    }

    /// The relay that knows the app secrets (the default one unless another is set).
    static var relay: URL { AppSettings.relayURL ?? URL(string: AppSettings.defaultRelayURL)! }

    /// Opens the provider's sign-in and returns the token bundle to store as the secret.
    @MainActor
    static func connect(_ kind: IntegrationKind, session: URLSession = .shared) async throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let state = Data(bytes.prefix(24)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = bytes.map { String(format: "%02x", $0) }.joined()
        let challenge = SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }.joined()

        var comps = URLComponents(url: relay.appending(path: "oauth/\(kind.rawValue)/start"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "state", value: state), .init(name: "challenge", value: challenge)]
        // The relay answers 503 when the provider isn't set up; check before opening a sheet onto an error page.
        var probe = URLRequest(url: comps.url!)
        probe.httpMethod = "HEAD"
        if let (_, r) = try? await session.data(for: probe), (r as? HTTPURLResponse)?.statusCode == 503 { throw Failure.notSetUp }

        let callback = try await WebSignIn().run(comps.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw Failure.failed }
        switch items.first(where: { $0.name == "error" })?.value {
        case "denied": throw Failure.denied
        case .some: throw Failure.failed
        case nil: break
        }

        var req = URLRequest(url: relay.appending(path: "oauth/handoff"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["state": state, "verifier": verifier])
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access"] as? String else { throw Failure.failed }
        let tokens = SocialTokens(access: access, refresh: obj["refresh"] as? String, expires: IntegrationSources.num(obj["expires"]),
                                  refreshExpires: obj["refreshExpires"].map(IntegrationSources.num), user: (obj["user"] as? String) ?? "")
        return tokens.json
    }

    /// Tokens good for the next request: renews them when they're close to running out and saves the
    /// new ones in the Keychain.
    static func tokens(_ i: Integration, secret: String, session: URLSession) async throws -> SocialTokens {
        guard var t = SocialTokens(secret) else { throw MetricsError.signInExpired }
        let now = Date().timeIntervalSince1970
        switch i.kind {
        case .tiktok:
            // Access tokens last a day; renewing needs the client secret, so the relay does it.
            guard t.expires - now < 10 * 60 else { return t }
            guard let refresh = t.refresh else { throw MetricsError.signInExpired }
            var req = IntegrationSources.request(relay.appending(path: "oauth/tiktok/refresh"), method: "POST",
                                                 headers: ["Content-Type": "application/json"],
                                                 body: try JSONSerialization.data(withJSONObject: ["refresh_token": refresh]))
            req.timeoutInterval = 20
            let obj: [String: Any]
            do { obj = try IntegrationSources.json(try await IntegrationSources.load(req, session: session)) as? [String: Any] ?? [:] }
            catch MetricsError.unauthorized { throw MetricsError.signInExpired }
            guard let access = obj["access"] as? String else { throw MetricsError.signInExpired }
            t.access = access
            t.refresh = (obj["refresh"] as? String) ?? t.refresh
            t.expires = IntegrationSources.num(obj["expires"])
            t.refreshExpires = obj["refreshExpires"].map(IntegrationSources.num) ?? t.refreshExpires
        case .instagram, .threads:
            // 60-day tokens, renewed without the secret once they're a day old. Renew in the last 50 days.
            guard t.expires - now < 50 * 86400 else { return t }
            let base = i.kind == .instagram ? "https://graph.instagram.com/refresh_access_token" : "https://graph.threads.net/refresh_access_token"
            var comps = URLComponents(string: base)!
            comps.queryItems = [.init(name: "grant_type", value: i.kind == .instagram ? "ig_refresh_token" : "th_refresh_token"),
                                .init(name: "access_token", value: t.access)]
            let obj = try? IntegrationSources.json(try await IntegrationSources.load(IntegrationSources.request(comps.url!), session: session)) as? [String: Any]
            guard let access = obj?["access_token"] as? String else {
                // Too new to renew, or a hiccup: fine while the old one still works.
                if t.expires > now { return t }
                throw MetricsError.signInExpired
            }
            t.access = access
            t.expires = now + IntegrationSources.num(obj?["expires_in"])
        default:
            return t
        }
        let saved = t.json
        await MainActor.run { Keychain.set(saved, for: i.keychainAccount) }
        return t
    }
}

/// The system's web sign-in sheet, which shares Safari's logins and hands back the prodline:// callback.
@MainActor
private final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme("prodline")) { callback, error in
                if let callback { cont.resume(returning: callback) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { cont.resume(throwing: SocialSignIn.Failure.cancelled) }
                else { cont.resume(throwing: SocialSignIn.Failure.failed) }
            }
            s.presentationContextProvider = self
            session = s
            if !s.start() { cont.resume(throwing: SocialSignIn.Failure.failed) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - The fetches

extension IntegrationSources {
    /// Views on videos posted since the start (newest first, so the list stops at the first older one).
    nonisolated static func tiktok(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let t = try await SocialSignIn.tokens(i, secret: secret, session: session)
        let auth = ["Authorization": "Bearer \(t.access)"]
        func call(_ req: URLRequest) async throws -> [String: Any] {
            let obj: [String: Any]
            do { obj = try json(try await load(req, session: session)) as? [String: Any] ?? [:] }
            catch MetricsError.unauthorized { throw MetricsError.signInExpired }
            let code = (obj["error"] as? [String: Any])?["code"] as? String ?? "ok"
            if code == "access_token_invalid" || code == "scope_not_authorized" { throw MetricsError.signInExpired }
            if code == "rate_limit_exceeded" { throw MetricsError.rateLimited(retryAfter: nil) }
            if code != "ok" { throw MetricsError.badPayload("TikTok said \(code)") }
            return obj["data"] as? [String: Any] ?? [:]
        }

        let since = start.startOfDay.timeIntervalSince1970
        var views = 0.0, posted = 0
        var cursor: Double?
        pages: for _ in 0..<25 {
            var body: [String: Any] = ["max_count": 20]
            if let cursor { body["cursor"] = cursor }
            let req = request(URL(string: "https://open.tiktokapis.com/v2/video/list/?fields=id,create_time,view_count")!, method: "POST",
                              headers: auth.merging(["Content-Type": "application/json"]) { a, _ in a },
                              body: try JSONSerialization.data(withJSONObject: body))
            let data = try await call(req)
            for v in (data["videos"] as? [[String: Any]]) ?? [] {
                if num(v["create_time"]) < since { break pages }
                views += num(v["view_count"])
                posted += 1
            }
            guard (data["has_more"] as? Bool) == true, data["cursor"] != nil else { break }
            cursor = num(data["cursor"])
        }
        let user = try await call(request(URL(string: "https://open.tiktokapis.com/v2/user/info/?fields=follower_count")!, headers: auth))

        var r = SourceResult()
        r.totals["social_views"] = views
        r.totals["videos_posted"] = Double(posted)
        if let u = user["user"] as? [String: Any], u["follower_count"] != nil { r.totals["followers"] = num(u["follower_count"]) }
        return r
    }

    /// Instagram's daily account views, one day per request. Days older than two are final and kept.
    nonisolated static func instagram(_ i: Integration, secret: String, start: Date, session: URLSession, cache: IntegrationCache) async throws -> SourceResult {
        let t = try await SocialSignIn.tokens(i, secret: secret, session: session)
        let api = "https://graph.instagram.com/v23.0/"
        func get(_ path: String, _ items: [URLQueryItem]) async throws -> [String: Any] {
            var comps = URLComponents(string: api + path)!
            comps.queryItems = items + [.init(name: "access_token", value: t.access)]
            do { return try json(try await load(request(comps.url!), session: session)) as? [String: Any] ?? [:] }
            catch MetricsError.unauthorized { throw MetricsError.signInExpired }
        }

        let bucket = i.id.uuidString + "|ig|" + t.user
        var stored = await cache.storedDays(bucket)
        let from = max(start.startOfDay, Date.now.startOfDay.adding(days: -maxBackfillDays))
        let all = days(from: from)
        let final = Date.now.startOfDay.adding(days: -2)
        // Missing finished days catch up a batch at a time; the last two days are asked again every time.
        let wanted = all.filter { $0 < final && stored[DayKey.string($0)] == nil }.suffix(dailyBatch) + all.filter { $0 >= final }
        var fresh: [String: [String: Double]] = [:], recent: [String: [String: Double]] = [:]
        for day in wanted {
            let obj = try await get("me/insights", [
                .init(name: "metric", value: "views"), .init(name: "period", value: "day"), .init(name: "metric_type", value: "total_value"),
                .init(name: "since", value: String(Int(day.timeIntervalSince1970))),
                .init(name: "until", value: String(Int(day.adding(days: 1).timeIntervalSince1970))),
            ])
            let entry = (obj["data"] as? [[String: Any]])?.first
            let value = num((entry?["total_value"] as? [String: Any])?["value"])
            if day < final { fresh[DayKey.string(day)] = ["social_views": value] } else { recent[DayKey.string(day)] = ["social_views": value] }
        }
        if !fresh.isEmpty { await cache.storeDays(bucket, fresh); stored.merge(fresh) { _, n in n } }

        var r = SourceResult()
        r.daily = stored.filter { $0.key >= DayKey.string(start) }.merging(recent) { _, n in n }
        r.dailyKeys = ["social_views"]
        r.totals["social_views"] = r.daily.values.reduce(0) { $0 + ($1["social_views"] ?? 0) }
        // Today isn't a finished day, so the history stops before it rather than at a half day.
        r.daily[DayKey.string(.now)] = nil
        let me = try await get("me", [.init(name: "fields", value: "followers_count")])
        if me["followers_count"] != nil { r.totals["followers"] = num(me["followers_count"]) }
        return r
    }

    /// Views on posts since the start (each post's own insights), plus followers.
    nonisolated static func threads(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let t = try await SocialSignIn.tokens(i, secret: secret, session: session)
        func get(_ path: String, _ items: [URLQueryItem]) async throws -> [String: Any] {
            var comps = URLComponents(string: "https://graph.threads.net/v1.0/" + path)!
            comps.queryItems = items + [.init(name: "access_token", value: t.access)]
            do { return try json(try await load(request(comps.url!), session: session)) as? [String: Any] ?? [:] }
            catch MetricsError.unauthorized { throw MetricsError.signInExpired }
        }

        var ids: [String] = []
        var after: String?
        for _ in 0..<5 {
            var q: [URLQueryItem] = [.init(name: "fields", value: "id"), .init(name: "limit", value: "100"),
                                     .init(name: "since", value: String(Int(max(start.startOfDay.timeIntervalSince1970, 1_712_991_600))))]
            if let after { q.append(.init(name: "after", value: after)) }
            let page = try await get("me/threads", q)
            ids += ((page["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
            guard let next = ((page["paging"] as? [String: Any])?["cursors"] as? [String: Any])?["after"] as? String,
                  (page["paging"] as? [String: Any])?["next"] != nil else { break }
            after = next
        }
        // Newest 100 posts at most per refresh: one request each.
        let views = try await withThrowingTaskGroup(of: Double.self) { group in
            for id in ids.prefix(100) {
                group.addTask {
                    let obj = try await get("\(id)/insights", [.init(name: "metric", value: "views")])
                    let values = ((obj["data"] as? [[String: Any]])?.first?["values"] as? [[String: Any]]) ?? []
                    return values.reduce(0) { $0 + num($1["value"]) }
                }
            }
            return try await group.reduce(0, +)
        }
        let followers = try await get("me/threads_insights", [.init(name: "metric", value: "followers_count")])
        let total = ((followers["data"] as? [[String: Any]])?.first?["total_value"] as? [String: Any])?["value"]

        var r = SourceResult()
        r.totals["social_views"] = views
        if total != nil { r.totals["followers"] = num(total) }
        return r
    }
}
