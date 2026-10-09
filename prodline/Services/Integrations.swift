import Foundation
import CryptoKit
import Compression

// MARK: - What can be connected
//
// Integrations talk to the services directly from the phone: no server in between. Settings that
// aren't secret (site, project or app IDs) live on the project; the key itself goes to the Keychain.
// Each one reports cumulative numbers since the project's start, like a custom endpoint does
// (docs/API.md), and daily steps where the service has them, so charts get a real history.

nonisolated enum IntegrationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case appStore, revenueCat, stripe, lemonSqueezy, gumroad, plausible, umami, youtube
    case shopify, paddle, polar, fathom, posthog, simpleAnalytics, vercel, netlify
    case kit, buttondown, beehiiv, npm, hackerNews, productHunt, bluesky

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case store = "Stores and packages", revenue = "Revenue", analytics = "Analytics", hosting = "Hosting"
        case newsletter = "Newsletters", social = "Social and launches"
    }

    var group: Group {
        switch self {
        case .appStore, .npm: .store
        case .revenueCat, .stripe, .lemonSqueezy, .gumroad, .shopify, .paddle, .polar: .revenue
        case .plausible, .umami, .fathom, .posthog, .simpleAnalytics: .analytics
        case .vercel, .netlify: .hosting
        case .kit, .buttondown, .beehiiv: .newsletter
        case .youtube, .hackerNews, .productHunt, .bluesky: .social
        }
    }

    var title: String {
        switch self {
        case .appStore: "App Store Connect"
        case .revenueCat: "RevenueCat"
        case .stripe: "Stripe"
        case .lemonSqueezy: "Lemon Squeezy"
        case .gumroad: "Gumroad"
        case .plausible: "Plausible"
        case .umami: "Umami"
        case .youtube: "YouTube"
        case .shopify: "Shopify"
        case .paddle: "Paddle"
        case .polar: "Polar"
        case .fathom: "Fathom Analytics"
        case .posthog: "PostHog"
        case .simpleAnalytics: "Simple Analytics"
        case .vercel: "Vercel"
        case .netlify: "Netlify"
        case .kit: "Kit"
        case .buttondown: "Buttondown"
        case .beehiiv: "beehiiv"
        case .npm: "npm"
        case .hackerNews: "Hacker News"
        case .productHunt: "Product Hunt"
        case .bluesky: "Bluesky"
        }
    }

    var symbol: String {
        switch self {
        case .appStore: "app.badge.fill"
        case .revenueCat: "arrow.triangle.2.circlepath"
        case .stripe: "creditcard.fill"
        case .lemonSqueezy: "cart.fill"
        case .gumroad: "bag.fill"
        case .plausible: "chart.bar.fill"
        case .umami: "chart.line.uptrend.xyaxis"
        case .youtube: "play.rectangle.fill"
        case .shopify: "storefront.fill"
        case .paddle: "dollarsign.square.fill"
        case .polar: "snowflake"
        case .fathom: "chart.pie.fill"
        case .posthog: "chart.bar.xaxis"
        case .simpleAnalytics: "chart.xyaxis.line"
        case .vercel: "triangle.fill"
        case .netlify: "square.stack.3d.up.fill"
        case .kit: "envelope.fill"
        case .buttondown: "envelope.badge.fill"
        case .beehiiv: "newspaper.fill"
        case .npm: "shippingbox.fill"
        case .hackerNews: "y.square.fill"
        case .productHunt: "p.circle.fill"
        case .bluesky: "cloud.fill"
        }
    }

    /// Official mark from the partner's brand kit (design/IMAGE_CREDITS.md). A full icon is shown as is;
    /// a wordmark sits on the brand color.
    var logo: (asset: String, isIcon: Bool)? {
        switch self {
        case .revenueCat: ("Logo-revenuecat", true)
        case .stripe: ("Logo-stripe", false)
        default: nil
        }
    }

    var colorHex: Int {
        switch self {
        case .appStore: 0x1C8CF5
        case .revenueCat: 0xF2545B
        case .stripe: 0x635BFF
        case .lemonSqueezy: 0xFFC233
        case .gumroad: 0xFF90E8
        case .plausible: 0x5850EC
        case .umami: 0x1C1C1E
        case .youtube: 0xFF0033
        case .shopify: 0x5E8E3E
        case .paddle: 0x2A2D34
        case .polar: 0x0062FF
        case .fathom: 0x2E3B4E
        case .posthog: 0xF54E00
        case .simpleAnalytics: 0xFF4F64
        case .vercel: 0x000000
        case .netlify: 0x00AD9F
        case .kit: 0xFB6970
        case .buttondown: 0x0069FF
        case .beehiiv: 0xE5A800
        case .npm: 0xCB3837
        case .hackerNews: 0xFF6600
        case .productHunt: 0xDA552F
        case .bluesky: 0x1185FE
        }
    }

    /// One line on what it brings in.
    var provides: String {
        switch self {
        case .appStore: "Downloads, proceeds and your star rating"
        case .revenueCat: "Revenue, MRR, subscribers and trials"
        case .stripe: "Revenue and sales"
        case .lemonSqueezy: "Revenue and orders"
        case .gumroad: "Revenue and sales"
        case .plausible: "Visitors and pageviews"
        case .umami: "Visitors and pageviews"
        case .youtube: "Views on videos posted since the start"
        case .shopify: "Revenue and orders"
        case .paddle: "Revenue and sales"
        case .polar: "Revenue and orders"
        case .fathom: "Visitors and pageviews"
        case .posthog: "Visitors and pageviews"
        case .simpleAnalytics: "Visitors and pageviews"
        case .vercel: "Deploys while you build"
        case .netlify: "Deploys while you build"
        case .kit: "New newsletter subscribers"
        case .buttondown: "New newsletter subscribers"
        case .beehiiv: "New newsletter subscribers"
        case .npm: "Package downloads"
        case .hackerNews: "Points on Hacker News posts about it"
        case .productHunt: "Upvotes on your launch"
        case .bluesky: "Followers"
        }
    }

    struct Field: Identifiable, Sendable {
        let key: String
        let label: String
        let placeholder: String
        var optional = false
        var multiline = false
        var id: String { key }
    }

    /// Non-secret settings, stored on the project.
    var fields: [Field] {
        switch self {
        case .appStore: [
            Field(key: "issuerID", label: "Issuer ID", placeholder: "57246542-96fe-1a63-e053-0824d011072a"),
            Field(key: "keyID", label: "Key ID", placeholder: "2X9R4HXF34"),
            Field(key: "vendor", label: "Vendor number", placeholder: "85912345"),
            Field(key: "appID", label: "App Apple ID", placeholder: "6478123456"),
            Field(key: "country", label: "Ratings storefront", placeholder: "us", optional: true),
        ]
        case .revenueCat: [Field(key: "projectID", label: "Project ID", placeholder: "proj1ab2c3d4")]
        case .stripe: []
        case .lemonSqueezy: [Field(key: "storeID", label: "Store ID", placeholder: "All stores", optional: true)]
        case .gumroad: []
        case .plausible: [
            Field(key: "site", label: "Site", placeholder: "yourapp.com"),
            Field(key: "base", label: "Server", placeholder: "https://plausible.io", optional: true),
        ]
        case .umami: [
            Field(key: "website", label: "Website ID", placeholder: "4fb7fa4c-5b46-438d-94b3-3a8fb9bc2e8b"),
            Field(key: "base", label: "API address", placeholder: "https://api.umami.is/v1", optional: true),
        ]
        case .youtube: [Field(key: "channel", label: "Channel", placeholder: "@yourchannel or UC…")]
        case .shopify: [Field(key: "shop", label: "Store address", placeholder: "your-store.myshopify.com")]
        case .paddle: [Field(key: "environment", label: "Environment", placeholder: "live (or sandbox)", optional: true)]
        case .polar: [Field(key: "organization", label: "Organization ID", placeholder: "All organizations", optional: true)]
        case .fathom: [Field(key: "site", label: "Site ID", placeholder: "ABCDEFG")]
        case .posthog: [
            Field(key: "projectID", label: "Project ID", placeholder: "12345"),
            Field(key: "host", label: "Host", placeholder: "https://us.posthog.com", optional: true),
        ]
        case .simpleAnalytics: [
            Field(key: "site", label: "Website", placeholder: "yourapp.com"),
            Field(key: "userID", label: "User ID", placeholder: "sa_user_id_…"),
        ]
        case .vercel: [
            Field(key: "projectID", label: "Project ID or name", placeholder: "prj_… or my-app"),
            Field(key: "teamID", label: "Team ID", placeholder: "team_… (for team projects)", optional: true),
        ]
        case .netlify: [Field(key: "site", label: "Site ID", placeholder: "3970e0fe-8564-4903-9a55-c5f8de49fb8b")]
        case .kit: []
        case .buttondown: []
        case .beehiiv: [Field(key: "publication", label: "Publication ID", placeholder: "pub_…")]
        case .npm: [Field(key: "package", label: "Package", placeholder: "your-package or @scope/package")]
        case .hackerNews: [Field(key: "url", label: "Website", placeholder: "yourapp.com")]
        case .productHunt: [Field(key: "slug", label: "Launch", placeholder: "producthunt.com/posts/your-app")]
        case .bluesky: [Field(key: "handle", label: "Handle", placeholder: "you.bsky.social")]
        }
    }

    var secretLabel: String {
        switch self {
        case .appStore: "Private key (.p8)"
        case .revenueCat: "Secret API key (v2)"
        case .stripe: "Restricted key"
        case .lemonSqueezy: "API key"
        case .gumroad: "Access token"
        case .plausible: "Stats API key"
        case .umami: "API key"
        case .youtube: "YouTube Data API key"
        case .shopify: "Admin API access token"
        case .paddle: "API key"
        case .polar: "Organization access token"
        case .fathom: "API token"
        case .posthog: "Personal API key"
        case .simpleAnalytics: "API key"
        case .vercel: "Access token"
        case .netlify: "Personal access token"
        case .kit: "API key (v4)"
        case .buttondown: "API key"
        case .beehiiv: "API key"
        case .productHunt: "Developer token"
        case .npm, .hackerNews, .bluesky: ""
        }
    }

    /// Public sources (npm, Hacker News, Bluesky) work without a key.
    var needsSecret: Bool { ![.npm, .hackerNews, .bluesky].contains(self) }

    var secretPlaceholder: String {
        switch self {
        case .appStore: "-----BEGIN PRIVATE KEY-----"
        case .revenueCat: "sk_…"
        case .stripe: "rk_live_…"
        case .youtube: "AIza…"
        case .shopify: "shpat_…"
        case .paddle: "pdl_live_apikey_…"
        case .polar: "polar_oat_…"
        case .posthog: "phx_…"
        case .simpleAnalytics: "sa_api_key_…"
        case .kit: "kit_…"
        default: "Paste the key"
        }
    }

    /// Where to find everything, step by step.
    var steps: [String] {
        switch self {
        case .appStore: [
            "In App Store Connect open Users and Access → Integrations → App Store Connect API.",
            "Create a team key with the Finance role (or Sales and Reports). Download the .p8 file: Apple only lets you do that once.",
            "Copy the Issuer ID (above the key list) and the key's Key ID.",
            "Vendor number: Payments and Financial Reports, top left. App Apple ID: your app → App Information.",
            "Open the .p8 file in Files or a text editor and paste its whole contents as the private key.",
            "Apple publishes sales a day later, so downloads lag about a day.",
        ]
        case .revenueCat: [
            "In RevenueCat open Project settings → API keys → + New secret API key.",
            "Choose API version 2 and give Charts & metrics read access (overview and charts). Nothing else.",
            "The project ID is in the address bar: app.revenuecat.com/projects/<this part>/…",
            "RevenueCat already counts App Store purchases, so with both connected revenue comes from RevenueCat only.",
        ]
        case .stripe: [
            "In the Stripe Dashboard open Developers → API keys → Create restricted key.",
            "Give it Read access to Balance (balance transactions). Leave everything else at None.",
            "Revenue is what customers paid since the project started, minus refunds.",
        ]
        case .lemonSqueezy: [
            "In Lemon Squeezy open Settings → API → + to create a key.",
            "The store ID is optional: leave it empty to count every store on the account.",
            "Revenue is paid orders since the project started, in USD.",
        ]
        case .gumroad: [
            "On Gumroad open Settings → Advanced. Under Applications, give it a name and icon, and enter http://127.0.0.1 as the Redirect URI (it isn't used).",
            "Click Create application, then Generate access token, and paste the token here. It doesn't expire until you revoke it.",
            "Revenue is sales since the project started, minus refunds.",
        ]
        case .plausible: [
            "In Plausible open your account settings → API keys → New API key, and pick Stats API.",
            "Site is the domain exactly as it appears in your Plausible dashboard.",
            "Self-hosting? Put your server's address in Server.",
        ]
        case .umami: [
            "Umami Cloud: Settings → API keys → Create key. The website ID is under Settings → Websites → Edit.",
            "Self-hosted: use your server's API address (https://your-umami.com/api) and an API token.",
        ]
        case .youtube: [
            "In the Google Cloud Console create a project (or pick one) and enable YouTube Data API v3 under APIs & Services → Library.",
            "Go to APIs & Services → Credentials → Create credentials → API key. Restrict it to YouTube Data API v3.",
            "Channel: your handle (@yourchannel) or the channel ID from YouTube → Settings → Advanced settings.",
            "Social views counts views on videos published since the project started, so older uploads don't inflate it. Videos posted gets the count, subscribers the channel total.",
        ]
        case .shopify: [
            "In your Shopify admin open Settings → Apps and sales channels → Develop apps, and create an app.",
            "Under Configuration give the Admin API the read_orders scope, then install the app.",
            "Reveal the Admin API access token once (it starts with shpat_) and paste it here.",
            "Revenue is what paid orders brought in since the project started, minus refunds and cancellations.",
        ]
        case .paddle: [
            "In Paddle open Developer tools → Authentication → API keys and create a key with read access to transactions.",
            "Using the sandbox? Type sandbox under Environment.",
            "Revenue is completed transactions since the project started, before Paddle's fees.",
        ]
        case .polar: [
            "In Polar open Settings → Developers → New token, and give it the orders:read scope.",
            "The organization ID is optional: leave it empty to count every organization the token sees.",
            "Revenue is paid orders since the project started, minus refunds.",
        ]
        case .fathom: [
            "In Fathom open Settings → API and create a token with access to the site (or all sites).",
            "The site ID is the code in your embed snippet (data-site=\"ABCDEFG\") and under Settings → Sites.",
        ]
        case .posthog: [
            "In PostHog click your avatar → Settings → Personal API keys → Create, with Query read access.",
            "The project ID is in the address bar: us.posthog.com/project/<this number>.",
            "On EU Cloud or self-hosted? Put the address under Host, e.g. https://eu.posthog.com.",
            "Visitors are unique people with a pageview, pageviews every $pageview event.",
        ]
        case .simpleAnalytics: [
            "In Simple Analytics open Account settings → API keys and create one. The user ID is shown on the same page.",
            "Website is the domain exactly as it appears in your dashboard.",
        ]
        case .vercel: [
            "In Vercel open Account settings → Tokens and create one, scoped to the team that owns the project.",
            "The project ID is under Project → Settings → General (prj_…); the project's name works too.",
            "For a team project, add the team ID from Team settings → General.",
            "Counts deploys since the project started: a good pulse while you build. Vercel has no public analytics API yet.",
        ]
        case .netlify: [
            "In Netlify open User settings → Applications → Personal access tokens → New access token.",
            "The site ID is under Site configuration → General → Site details (Site ID).",
            "Counts successful deploys since the project started. Netlify has no public analytics API yet.",
        ]
        case .kit: [
            "In Kit open Settings → Developer → API keys (v4) and add a key.",
            "Counts active subscribers who joined since the project started.",
        ]
        case .buttondown: [
            "In Buttondown open Settings → API and copy your API key.",
            "Counts subscribers who joined since the project started.",
        ]
        case .beehiiv: [
            "In beehiiv open Settings → API → Create new API key.",
            "The publication ID is on the same page (pub_…).",
            "Counts active subscribers who joined since the project started.",
        ]
        case .npm: [
            "No key needed: npm's download counts are public.",
            "Type the package name as published, e.g. left-pad or @scope/package.",
            "npm publishes counts a day later.",
        ]
        case .hackerNews: [
            "No key needed: posts come from Hacker News search.",
            "Type your website. Points add up on every post linking to it since the project started.",
        ]
        case .productHunt: [
            "On Product Hunt open API Dashboard (producthunt.com/v2/oauth/applications) → Add an application.",
            "Use any name and https://localhost as the redirect URI, then click Create Token for a developer token.",
            "Paste your launch's address or just its slug.",
        ]
        case .bluesky: [
            "No key needed: Bluesky profiles are public.",
            "Followers is the account's total right now.",
        ]
        }
    }
}

nonisolated struct Integration: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: IntegrationKind
    var fields: [String: String] = [:]

    var keychainAccount: String { "int-" + id.uuidString }
    func field(_ key: String) -> String { (fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Everything needed is filled in (the key is checked separately).
    var isComplete: Bool { kind.fields.allSatisfy { $0.optional || !field($0.key).isEmpty } }
}

// MARK: - Metrics a source reports

/// Totals right now, plus per-day steps (`yyyy-MM-dd` → key → amount added that day) for the days the
/// source could account for. Days missing from `daily` aren't known yet (not "zero").
nonisolated struct SourceResult: Sendable, Equatable {
    var totals: [String: Double] = [:]
    var daily: [String: [String: Double]] = [:]
    /// Keys with a daily history; others are only known as a current value (e.g. MRR, rating).
    var dailyKeys: Set<String> = []
}

nonisolated enum IntegrationMetric {
    /// Extra keys the integrations add, with how to show them.
    static func title(_ key: String) -> String {
        switch key {
        case "mrr": "MRR"
        case "arr": "ARR"
        case "active_subscriptions": "Subscribers"
        case "active_trials": "Trials"
        case "app_store_proceeds": "App Store proceeds"
        case "rating": "Rating"
        case "videos_posted": "Videos posted"
        case "ratings": "Ratings"
        case "deploys": "Deploys"
        case "new_subscribers": "New subscribers"
        case "followers": "Followers"
        case "hn_points": "HN points"
        case "upvotes": "Upvotes"
        case "hn_comments": "HN comments"
        case "ph_comments": "Product Hunt comments"
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func format(_ key: String, _ value: Double) -> String {
        switch key {
        case "mrr", "arr", "app_store_proceeds": MetricKey.money(value)
        case "rating": value.formatted(.number.precision(.fractionLength(1))) + " ★"
        default: MetricKey.count(value)
        }
    }
}

// MARK: - The client the refresher uses

/// All of a project's integrations (and its own endpoint, if it has one) as one metrics feed.
nonisolated struct IntegrationsClient: MetricsClient {
    let integrations: [(Integration, String)]
    let start: Date
    let endpoint: (any MetricsClient)?
    var session: URLSession = .shared

    func fetch(since: Date?) async throws -> MetricsPayload {
        let now = Date()
        async let custom: MetricsPayload? = { try? await endpoint?.fetch(since: nil) }()
        let results = await withTaskGroup(of: (IntegrationKind, Result<SourceResult, Error>).self) { group in
            for (integration, secret) in integrations {
                group.addTask {
                    do { return (integration.kind, .success(try await IntegrationCache.shared.result(for: integration, secret: secret, start: start, session: session))) }
                    catch { return (integration.kind, .failure(error)) }
                }
            }
            var out: [(IntegrationKind, Result<SourceResult, Error>)] = []
            for await r in group { out.append(r) }
            return out
        }
        let good = results.compactMap { r -> (IntegrationKind, SourceResult)? in
            if case .success(let s) = r.1 { return (r.0, s) } else { return nil }
        }
        let endpointPayload = await custom
        if good.isEmpty, endpointPayload == nil, let first = results.first, case .failure(let e) = first.1 {
            throw (e as? MetricsError) ?? MetricsError.offline(e.localizedDescription)
        }
        return Self.combine(good, endpoint: endpointPayload, start: start, now: now)
    }

    /// Adds sources up. RevenueCat already counts App Store purchases, so App Store proceeds only
    /// count as revenue without it. The endpoint fills in whatever the integrations don't cover.
    static func combine(_ sources: [(IntegrationKind, SourceResult)], endpoint: MetricsPayload?, start: Date, now: Date) -> MetricsPayload {
        let hasRevenueCat = sources.contains { $0.0 == .revenueCat }
        var parts: [SourceResult] = sources.map { kind, r in
            guard kind == .appStore, hasRevenueCat else { return r }
            var r = r
            r.totals["revenue"] = nil
            r.dailyKeys.remove("revenue")
            for d in r.daily.keys { r.daily[d]?["revenue"] = nil }
            return r
        }
        parts.removeAll { $0.totals.isEmpty }

        var totals: [String: Double] = [:]
        for p in parts { for (k, v) in p.totals { totals[k, default: 0] += v } }
        // A rating doesn't add up across sources.
        if let rating = parts.compactMap({ $0.totals["rating"] }).first { totals["rating"] = rating }
        var metrics = totals.map { MetricsPayload.Metric(key: $0.key, value: $0.value, unit: $0.key == "revenue" ? "USD" : nil) }
        for m in endpoint?.metrics ?? [] where totals[m.key] == nil { metrics.append(m) }
        metrics.sort { $0.key < $1.key }

        // History: one point per finished day, only while every source accounts for that day.
        var history: [MetricsPayload.Point] = []
        let historyKeys = Set(parts.flatMap(\.dailyKeys))
        if !historyKeys.isEmpty {
            var running: [String: Double] = [:]
            var day = start.startOfDay
            let today = now.startOfDay
            let endpointHistory = (endpoint?.history ?? []).sorted { $0.asOf < $1.asOf }
            while day < today {
                let key = DayKey.string(day)
                let known = parts.allSatisfy { $0.dailyKeys.isEmpty || $0.daily[key] != nil }
                guard known else { break }
                for p in parts { for (k, v) in p.daily[key] ?? [:] where p.dailyKeys.contains(k) { running[k, default: 0] += v } }
                let end = day.adding(days: 1).addingTimeInterval(-60)
                var pm = running.map { MetricsPayload.Metric(key: $0.key, value: $0.value) }
                // Keys only the endpoint has: its last value up to that day.
                if let ep = endpointHistory.last(where: { $0.asOf <= end }) {
                    for m in ep.metrics where running[m.key] == nil && !historyKeys.contains(m.key) { pm.append(m) }
                }
                history.append(.init(asOf: end, metrics: pm))
                day = day.adding(days: 1)
            }
        }
        return MetricsPayload(schemaVersion: 1, project: nil, asOf: now, metrics: metrics, history: history, goals: endpoint?.goals)
    }
}

nonisolated enum DayKey {
    static func string(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    /// Same calendar day in UTC (APIs that take plain dates).
    static func utcString(_ d: Date) -> String { string(d) }
}

// MARK: - Cache: the foreground poll runs every 30 s; services get asked every 15 minutes at most

actor IntegrationCache {
    static let shared = IntegrationCache()
    static let ttl: TimeInterval = 15 * 60

    private var memory: [String: (at: Date, result: SourceResult)] = [:]
    /// Finished days that won't change (App Store reports, RevenueCat daily revenue), kept on disk.
    private var days: [String: [String: [String: Double]]] = [:]
    private var loaded = false

    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("integration-days.json")
    }

    func result(for integration: Integration, secret: String, start: Date, session: URLSession, force: Bool = false) async throws -> SourceResult {
        let key = cacheKey(integration, secret: secret, start: start)
        if !force, let hit = memory[key], Date().timeIntervalSince(hit.at) < Self.ttl { return hit.result }
        let r = try await IntegrationSources.fetch(integration, secret: secret, start: start, session: session, cache: self)
        memory[key] = (Date(), r)
        return r
    }

    func forget(_ integration: Integration) {
        memory = memory.filter { !$0.key.hasPrefix(integration.id.uuidString) }
        loadIfNeeded()
        days = days.filter { !$0.key.hasPrefix(integration.id.uuidString) }
        save()
    }

    private func cacheKey(_ i: Integration, secret: String, start: Date) -> String {
        "\(i.id.uuidString)|\(i.fields.sorted { $0.key < $1.key })|\(secret.hashValue)|\(start.timeIntervalSince1970)"
    }

    func storedDays(_ bucket: String) -> [String: [String: Double]] {
        loadIfNeeded()
        return days[bucket] ?? [:]
    }

    func storeDays(_ bucket: String, _ values: [String: [String: Double]]) {
        loadIfNeeded()
        days[bucket, default: [:]].merge(values) { _, new in new }
        save()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let d = try? JSONDecoder().decode([String: [String: [String: Double]]].self, from: data) { days = d }
    }

    private func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - The services

nonisolated enum IntegrationSources {
    /// Days fetched one request at a time (App Store, RevenueCat) catch up this many per pass.
    static let dailyBatch = 20
    /// How far back those go.
    static let maxBackfillDays = 90

    static func fetch(_ i: Integration, secret: String, start: Date, session: URLSession, cache: IntegrationCache) async throws -> SourceResult {
        guard !secret.isEmpty || !i.kind.needsSecret else { throw MetricsError.unauthorized }
        switch i.kind {
        case .appStore: return try await appStore(i, secret: secret, start: start, session: session, cache: cache)
        case .revenueCat: return try await revenueCat(i, secret: secret, start: start, session: session, cache: cache)
        case .stripe: return try await stripe(secret: secret, start: start, session: session)
        case .lemonSqueezy: return try await lemonSqueezy(i, secret: secret, start: start, session: session)
        case .gumroad: return try await gumroad(secret: secret, start: start, session: session)
        case .plausible: return try await plausible(i, secret: secret, start: start, session: session)
        case .umami: return try await umami(i, secret: secret, start: start, session: session)
        case .youtube: return try await youtube(i, secret: secret, start: start, session: session)
        case .shopify: return try await shopify(i, secret: secret, start: start, session: session)
        case .paddle: return try await paddle(i, secret: secret, start: start, session: session)
        case .polar: return try await polar(i, secret: secret, start: start, session: session)
        case .fathom: return try await fathom(i, secret: secret, start: start, session: session)
        case .posthog: return try await posthog(i, secret: secret, start: start, session: session)
        case .simpleAnalytics: return try await simpleAnalytics(i, secret: secret, start: start, session: session)
        case .vercel: return try await vercel(i, secret: secret, start: start, session: session)
        case .netlify: return try await netlify(i, secret: secret, start: start, session: session)
        case .kit: return try await kit(secret: secret, start: start, session: session)
        case .buttondown: return try await buttondown(secret: secret, start: start, session: session)
        case .beehiiv: return try await beehiiv(i, secret: secret, start: start, session: session)
        case .npm: return try await npm(i, start: start, session: session)
        case .hackerNews: return try await hackerNews(i, start: start, session: session)
        case .productHunt: return try await productHunt(i, secret: secret, session: session)
        case .bluesky: return try await bluesky(i, session: session)
        }
    }

    // MARK: HTTP

    static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Prodline/1.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    /// Data for a 2xx answer; maps the usual failures to readable errors. `allow404` returns nil instead.
    static func load(_ req: URLRequest, session: URLSession, allow404: Bool = false) async throws -> Data? {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch let e as URLError {
            throw MetricsError.offline(e.code == .notConnectedToInternet ? "You're offline." : "Can't reach \(req.url?.host() ?? "the service").")
        }
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw MetricsError.unauthorized
        case 404 where allow404: return nil
        case 404: throw MetricsError.badPayload("not found (404). Check the IDs.")
        case 429: throw MetricsError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        default: throw MetricsError.server(http.statusCode)
        }
    }

    static func json(_ data: Data?) throws -> Any {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else { throw MetricsError.badPayload("not valid JSON") }
        return obj
    }

    static func iso(_ s: String?) -> Date? { s.flatMap(MetricsPayload.parseDate) ?? s.flatMap { str in
        // "2026-10-05 12:00:00" style
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f.date(from: String(str.prefix(19)))
    } }

    /// Every day from `start` through today, oldest first.
    static func days(from start: Date, to now: Date = .now) -> [Date] {
        var out: [Date] = []
        var d = start.startOfDay
        while d <= now.startOfDay { out.append(d); d = d.adding(days: 1) }
        return out
    }

    /// Per-day sums of dated amounts, filling quiet days with zero so the history has no gaps.
    static func dailyFrom(_ items: [(Date, [String: Double])], start: Date, keys: Set<String>) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for d in days(from: start) { out[DayKey.string(d)] = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) }) }
        for (date, values) in items where date >= start.startOfDay {
            let k = DayKey.string(date)
            for (key, v) in values { out[k, default: [:]][key, default: 0] += v }
        }
        return out
    }

    // MARK: Currency (proceeds come in many currencies; the app shows USD)

    nonisolated final class Rates: @unchecked Sendable {
        static let shared = Rates()
        private let lock = NSLock()
        private var rates: [String: Double] = [:]
        private var fetched: Date?

        /// USD per unit of `currency`; nil if unknown.
        func usd(_ amount: Double, _ currency: String, session: URLSession) async -> Double? {
            let cur = currency.uppercased()
            if cur == "USD" || cur.isEmpty { return amount }
            let stale = lock.withLock { fetched.map { Date().timeIntervalSince($0) > 12 * 3600 } ?? true }
            if stale, let data = try? await IntegrationSources.load(IntegrationSources.request(URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")!), session: session),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = obj["rates"] as? [String: Double] {
                lock.withLock { rates = r; fetched = Date() }
            }
            return lock.withLock { rates[cur].map { amount / $0 } }
        }
    }

    // MARK: App Store Connect

    static func appStoreToken(issuer: String, keyID: String, pem: String, now: Date = .now) throws -> String {
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(pemRepresentation: pem.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { throw MetricsError.badPayload("the private key isn't a valid .p8 file") }
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"], options: .sortedKeys)
        let iat = Int(now.timeIntervalSince1970)
        let payload = try JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": iat, "exp": iat + 15 * 60, "aud": "appstoreconnect-v1"],
                                                 options: .sortedKeys)
        let input = b64(header) + "." + b64(payload)
        let sig = try key.signature(for: Data(input.utf8))
        return input + "." + b64(sig.rawRepresentation)
    }

    /// Product types that are a first download (not an update, redownload or in-app purchase).
    static let firstDownloadTypes: Set<String> = ["1", "1F", "1T", "F1", "1E", "1EP", "1EU", "1-B", "F1-B"]

    /// Parsed rows of one day's summary sales report for the app (and its in-app purchases).
    static func parseSalesReport(_ tsv: String, appID: String) -> (downloads: Double, proceeds: [(Double, String)]) {
        var lines = tsv.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard !lines.isEmpty else { return (0, []) }
        let header = lines.removeFirst()
        func col(_ name: String) -> Int? { header.firstIndex { $0.hasPrefix(name) } }
        guard let type = col("Product Type Identifier"), let units = col("Units"), let proceeds = col("Developer Proceeds"),
              let currency = col("Currency of Proceeds"), let apple = col("Apple Identifier") else { return (0, []) }
        let sku = col("SKU"), parent = col("Parent Identifier")
        let appSKUs = Set(lines.filter { $0[safe: apple] == appID }.compactMap { sku.flatMap($0.indices.contains) == true ? $0[sku!] : nil })
        var downloads = 0.0
        var money: [(Double, String)] = []
        for row in lines {
            let isApp = row[safe: apple] == appID
            let isPurchase = parent.flatMap { row[safe: $0] }.map { !$0.isEmpty && appSKUs.contains($0) } ?? false
            guard isApp || isPurchase else { continue }
            let n = Double(row[safe: units] ?? "") ?? 0
            if isApp, firstDownloadTypes.contains(row[safe: type] ?? "") { downloads += n }
            let each = Double(row[safe: proceeds] ?? "") ?? 0
            if each != 0 { money.append((each * n, row[safe: currency] ?? "USD")) }
        }
        return (downloads, money)
    }

    static func appStore(_ i: Integration, secret: String, start: Date, session: URLSession, cache: IntegrationCache) async throws -> SourceResult {
        let token = try appStoreToken(issuer: i.field("issuerID"), keyID: i.field("keyID"), pem: secret)
        let appID = i.field("appID")
        let bucket = i.id.uuidString + "|asc|" + appID
        var stored = await cache.storedDays(bucket)
        let from = max(start.startOfDay, Date.now.startOfDay.adding(days: -maxBackfillDays))
        // Reports exist from yesterday back; a missing report older than two days means no sales.
        let wanted = days(from: from, to: Date.now.adding(days: -1)).filter { stored[DayKey.string($0)] == nil }
        var fresh: [String: [String: Double]] = [:]
        for day in wanted.suffix(dailyBatch).reversed() {
            var comps = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/salesReports")!
            comps.queryItems = [
                .init(name: "filter[frequency]", value: "DAILY"), .init(name: "filter[reportType]", value: "SALES"),
                .init(name: "filter[reportSubType]", value: "SUMMARY"), .init(name: "filter[vendorNumber]", value: i.field("vendor")),
                .init(name: "filter[reportDate]", value: DayKey.string(day)), .init(name: "filter[version]", value: "1_1"),
            ]
            let req = request(comps.url!, headers: ["Authorization": "Bearer \(token)", "Accept": "application/a-gzip"])
            let data = try await load(req, session: session, allow404: true)
            let key = DayKey.string(day)
            guard let data else {
                if Date.days(from: day, to: .now) > 2 { fresh[key] = ["downloads": 0, "revenue": 0] }
                continue
            }
            let text = String(decoding: Gzip.inflate(data) ?? data, as: UTF8.self)
            let parsed = parseSalesReport(text, appID: appID)
            var usd = 0.0
            for (amount, cur) in parsed.proceeds { usd += await Rates.shared.usd(amount, cur, session: session) ?? 0 }
            fresh[key] = ["downloads": parsed.downloads, "revenue": (usd * 100).rounded() / 100]
        }
        if !fresh.isEmpty { await cache.storeDays(bucket, fresh); stored.merge(fresh) { _, n in n } }

        var r = SourceResult()
        r.daily = stored.filter { $0.key >= DayKey.string(start) }
        r.dailyKeys = ["downloads", "revenue"]
        r.totals["downloads"] = r.daily.values.reduce(0) { $0 + ($1["downloads"] ?? 0) }
        let proceeds = r.daily.values.reduce(0) { $0 + ($1["revenue"] ?? 0) }
        r.totals["revenue"] = proceeds
        r.totals["app_store_proceeds"] = proceeds

        // Rating: the public lookup needs no key.
        let country = i.field("country").isEmpty ? "us" : i.field("country").lowercased()
        if let url = URL(string: "https://itunes.apple.com/lookup?id=\(appID)&country=\(country)"),
           let data = try? await load(request(url), session: session),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let app = (obj["results"] as? [[String: Any]])?.first {
            if let avg = app["averageUserRating"] as? Double { r.totals["rating"] = (avg * 10).rounded() / 10 }
            if let n = app["userRatingCount"] as? Double { r.totals["ratings"] = n } else if let n = app["userRatingCount"] as? Int { r.totals["ratings"] = Double(n) }
        }
        return r
    }

    // MARK: RevenueCat

    static func revenueCat(_ i: Integration, secret: String, start: Date, session: URLSession, cache: IntegrationCache) async throws -> SourceResult {
        let base = "https://api.revenuecat.com/v2/projects/\(i.field("projectID"))/metrics"
        let auth = ["Authorization": "Bearer \(secret)", "Accept": "application/json"]
        var r = SourceResult()

        let overview = try json(try await load(request(URL(string: base + "/overview?currency=USD")!, headers: auth), session: session))
        for m in ((overview as? [String: Any])?["metrics"] as? [[String: Any]]) ?? [] {
            guard let id = m["id"] as? String, let v = (m["value"] as? Double) ?? (m["value"] as? Int).map(Double.init) else { continue }
            if ["mrr", "active_subscriptions", "active_trials"].contains(id) { r.totals[id] = v }
        }

        func revenue(_ from: Date, _ to: Date) async throws -> Double {
            let url = URL(string: base + "/revenue?start_date=\(DayKey.string(from))&end_date=\(DayKey.string(to))&currency=USD")!
            let obj = try json(try await load(request(url, headers: auth), session: session)) as? [String: Any]
            return (obj?["value"] as? Double) ?? (obj?["value"] as? Int).map(Double.init) ?? 0
        }
        r.totals["revenue"] = try await revenue(start, .now)

        // Daily revenue for the history, a batch at a time; finished days never change.
        let bucket = i.id.uuidString + "|rc|" + i.field("projectID")
        var stored = await cache.storedDays(bucket)
        let from = max(start.startOfDay, Date.now.startOfDay.adding(days: -maxBackfillDays))
        var fresh: [String: [String: Double]] = [:]
        for day in days(from: from, to: Date.now.adding(days: -1)).filter({ stored[DayKey.string($0)] == nil }).prefix(dailyBatch) {
            fresh[DayKey.string(day)] = ["revenue": try await revenue(day, day)]
        }
        if !fresh.isEmpty { await cache.storeDays(bucket, fresh); stored.merge(fresh) { _, n in n } }
        r.daily = stored.filter { $0.key >= DayKey.string(start) }
        // Before the backfill reaches the start, there's no complete history to draw.
        r.dailyKeys = from == start.startOfDay ? ["revenue"] : []
        return r
    }

    // MARK: Stripe

    static func stripe(secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        var after: String?
        for _ in 0..<50 {
            var comps = URLComponents(string: "https://api.stripe.com/v1/balance_transactions")!
            comps.queryItems = [.init(name: "limit", value: "100"), .init(name: "created[gte]", value: String(Int(start.startOfDay.timeIntervalSince1970)))]
            if let after { comps.queryItems?.append(.init(name: "starting_after", value: after)) }
            let obj = try json(try await load(request(comps.url!, headers: ["Authorization": "Bearer \(secret)"]), session: session)) as? [String: Any]
            let rows = (obj?["data"] as? [[String: Any]]) ?? []
            for t in rows {
                guard let type = t["type"] as? String, ["charge", "payment", "refund", "payment_refund"].contains(type),
                      let cents = (t["amount"] as? Int).map(Double.init) ?? (t["amount"] as? Double),
                      let created = (t["created"] as? Int).map({ Date(timeIntervalSince1970: TimeInterval($0)) }) else { continue }
                let amount = await Rates.shared.usd(cents / 100, (t["currency"] as? String) ?? "usd", session: session) ?? 0
                let sale: Double = type == "charge" || type == "payment" ? 1 : 0
                items.append((created, ["revenue": amount, "sales": sale]))
            }
            guard (obj?["has_more"] as? Bool) == true, let last = rows.last?["id"] as? String else { break }
            after = last
        }
        return summed(items, start: start, keys: ["revenue", "sales"])
    }

    // MARK: Lemon Squeezy

    static func lemonSqueezy(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        page: for n in 1...50 {
            var comps = URLComponents(string: "https://api.lemonsqueezy.com/v1/orders")!
            comps.queryItems = [.init(name: "page[size]", value: "100"), .init(name: "page[number]", value: String(n))]
            if !i.field("storeID").isEmpty { comps.queryItems?.append(.init(name: "filter[store_id]", value: i.field("storeID"))) }
            let req = request(comps.url!, headers: ["Authorization": "Bearer \(secret)", "Accept": "application/vnd.api+json"])
            let obj = try json(try await load(req, session: session)) as? [String: Any]
            let rows = (obj?["data"] as? [[String: Any]]) ?? []
            for row in rows {
                guard let a = row["attributes"] as? [String: Any], let created = iso(a["created_at"] as? String) else { continue }
                // Newest first: once past the start, the rest is older too.
                if created < start.startOfDay { break page }
                guard (a["status"] as? String) == "paid", (a["refunded"] as? Bool) != true else { continue }
                let cents = (a["total_usd"] as? Double) ?? (a["total_usd"] as? Int).map(Double.init) ?? 0
                items.append((created, ["revenue": cents / 100, "sales": 1]))
            }
            let meta = (obj?["meta"] as? [String: Any])?["page"] as? [String: Any]
            let lastPage = (meta?["lastPage"] as? Int) ?? n
            if rows.isEmpty || n >= lastPage { break }
        }
        return summed(items, start: start, keys: ["revenue", "sales"])
    }

    // MARK: Gumroad

    static func gumroad(secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        var pageKey: String?
        for _ in 0..<50 {
            var comps = URLComponents(string: "https://api.gumroad.com/v2/sales")!
            comps.queryItems = [.init(name: "access_token", value: secret), .init(name: "after", value: DayKey.string(start.adding(days: -1)))]
            if let pageKey { comps.queryItems?.append(.init(name: "page_key", value: pageKey)) }
            let req = request(comps.url!, headers: ["Authorization": "Bearer \(secret)"])
            let obj = try json(try await load(req, session: session)) as? [String: Any]
            for s in (obj?["sales"] as? [[String: Any]]) ?? [] {
                guard let created = iso(s["created_at"] as? String), (s["refunded"] as? Bool) != true else { continue }
                let cents = (s["price"] as? Double) ?? (s["price"] as? Int).map(Double.init) ?? 0
                items.append((created, ["revenue": cents / 100, "sales": 1]))
            }
            guard let next = obj?["next_page_key"] as? String, !next.isEmpty else { break }
            pageKey = next
        }
        return summed(items, start: start, keys: ["revenue", "sales"])
    }

    // MARK: Plausible

    static func plausible(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let base = i.field("base").isEmpty ? "https://plausible.io" : i.field("base").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/v2/query") else { throw MetricsError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: [
            "site_id": i.field("site"), "metrics": ["visitors", "pageviews"],
            "date_range": [DayKey.string(start), DayKey.string(.now)], "dimensions": ["time:day"],
        ])
        let req = request(url, method: "POST", headers: ["Authorization": "Bearer \(secret)", "Content-Type": "application/json"], body: body)
        let obj = try json(try await load(req, session: session)) as? [String: Any]
        var items: [(Date, [String: Double])] = []
        for row in (obj?["results"] as? [[String: Any]]) ?? [] {
            guard let day = (row["dimensions"] as? [String])?.first.flatMap(MetricsPayload.parseDate),
                  let m = row["metrics"] as? [Any], m.count >= 2 else { continue }
            func num(_ x: Any) -> Double { (x as? Double) ?? (x as? Int).map(Double.init) ?? 0 }
            items.append((day, ["visits": num(m[0]), "pageviews": num(m[1])]))
        }
        return summed(items, start: start, keys: ["visits", "pageviews"])
    }

    // MARK: Umami

    static func umami(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let base = i.field("base").isEmpty ? "https://api.umami.is/v1" : i.field("base").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var comps = URLComponents(string: base + "/websites/\(i.field("website"))/pageviews")
        comps?.queryItems = [
            .init(name: "startAt", value: String(Int(start.startOfDay.timeIntervalSince1970 * 1000))),
            .init(name: "endAt", value: String(Int(Date.now.timeIntervalSince1970 * 1000))),
            .init(name: "unit", value: "day"), .init(name: "timezone", value: TimeZone.current.identifier),
        ]
        guard let url = comps?.url else { throw MetricsError.invalidURL }
        // Umami Cloud reads x-umami-api-key; a self-hosted server reads the bearer token.
        let req = request(url, headers: ["x-umami-api-key": secret, "Authorization": "Bearer \(secret)", "Accept": "application/json"])
        let obj = try json(try await load(req, session: session)) as? [String: Any]
        var items: [(Date, [String: Double])] = []
        for (series, key) in [("sessions", "visits"), ("pageviews", "pageviews")] {
            for p in (obj?[series] as? [[String: Any]]) ?? [] {
                guard let d = iso(p["x"] as? String) else { continue }
                let y = (p["y"] as? Double) ?? (p["y"] as? Int).map(Double.init) ?? 0
                items.append((d, [key: y]))
            }
        }
        return summed(items, start: start, keys: ["visits", "pageviews"])
    }

    // MARK: YouTube

    /// Views on the videos uploaded since the project started (the uploads playlist, newest first), plus the
    /// channel's subscribers. View counts are only known as totals, so there's no daily history.
    static func youtube(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let api = "https://www.googleapis.com/youtube/v3"
        func get(_ path: String, _ items: [URLQueryItem]) async throws -> [String: Any] {
            var comps = URLComponents(string: api + path)!
            comps.queryItems = items + [.init(name: "key", value: secret)]
            let obj = try json(try await load(request(comps.url!), session: session)) as? [String: Any]
            return obj ?? [:]
        }
        func number(_ x: Any?) -> Double { (x as? String).flatMap(Double.init) ?? (x as? Double) ?? (x as? Int).map(Double.init) ?? 0 }

        let channel = i.field("channel")
        let lookup: URLQueryItem = channel.hasPrefix("UC") && !channel.hasPrefix("@")
            ? .init(name: "id", value: channel)
            : .init(name: "forHandle", value: channel.hasPrefix("@") ? channel : "@" + channel)
        let ch = try await get("/channels", [.init(name: "part", value: "statistics,contentDetails"), lookup])
        guard let item = (ch["items"] as? [[String: Any]])?.first else {
            throw MetricsError.badPayload("no channel found for \(channel)")
        }
        let stats = item["statistics"] as? [String: Any]
        let uploads = ((item["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any])?["uploads"] as? String

        var ids: [String] = []
        if let uploads {
            var page: String?
            pages: for _ in 0..<10 {
                var q: [URLQueryItem] = [.init(name: "part", value: "contentDetails"), .init(name: "playlistId", value: uploads),
                                         .init(name: "maxResults", value: "50")]
                if let page { q.append(.init(name: "pageToken", value: page)) }
                let list = try await get("/playlistItems", q)
                for v in (list["items"] as? [[String: Any]]) ?? [] {
                    guard let cd = v["contentDetails"] as? [String: Any], let id = cd["videoId"] as? String else { continue }
                    // Newest first: once a video predates the project, so do the rest.
                    if let at = iso(cd["videoPublishedAt"] as? String), at < start.startOfDay { break pages }
                    ids.append(id)
                }
                guard let next = list["nextPageToken"] as? String else { break }
                page = next
            }
        }
        var views = 0.0
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            let vids = try await get("/videos", [.init(name: "part", value: "statistics"), .init(name: "id", value: chunk.joined(separator: ","))])
            for v in (vids["items"] as? [[String: Any]]) ?? [] { views += number((v["statistics"] as? [String: Any])?["viewCount"]) }
        }

        var r = SourceResult()
        r.totals["social_views"] = views
        r.totals["videos_posted"] = Double(ids.count)
        if (stats?["hiddenSubscriberCount"] as? Bool) != true { r.totals["subscribers"] = number(stats?["subscriberCount"]) }
        return r
    }

    // MARK: Shared parsing

    static func num(_ x: Any?) -> Double {
        (x as? Double) ?? (x as? Int).map(Double.init) ?? (x as? String).flatMap(Double.init) ?? 0
    }

    static func isoString(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    /// "https://shop.example.com/" → "shop.example.com".
    static func host(_ s: String) -> String {
        var h = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["https://", "http://"] where h.hasPrefix(p) { h.removeFirst(p.count) }
        return h.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: Shopify

    /// Paid orders through the Admin GraphQL API, minus refunds; cancelled orders don't count.
    static func shopify(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var shop = host(i.field("shop"))
        if !shop.contains(".") { shop += ".myshopify.com" }
        guard let url = URL(string: "https://\(shop)/admin/api/2025-07/graphql.json") else { throw MetricsError.invalidURL }
        var items: [(Date, [String: Double])] = []
        var cursor: String?
        for _ in 0..<40 {
            let after = cursor.map { ", after: \"\($0)\"" } ?? ""
            let query = """
            { orders(first: 250\(after), sortKey: CREATED_AT, query: "created_at:>=\(DayKey.string(start))") {
                edges { node { createdAt cancelledAt displayFinancialStatus
                    totalPriceSet { shopMoney { amount currencyCode } } totalRefundedSet { shopMoney { amount } } } }
                pageInfo { hasNextPage endCursor } } }
            """
            let body = try JSONSerialization.data(withJSONObject: ["query": query])
            let req = request(url, method: "POST", headers: ["X-Shopify-Access-Token": secret, "Content-Type": "application/json"], body: body)
            let obj = try json(try await load(req, session: session)) as? [String: Any]
            if let err = (obj?["errors"] as? [[String: Any]])?.first?["message"] as? String { throw MetricsError.badPayload(err) }
            let orders = (obj?["data"] as? [String: Any])?["orders"] as? [String: Any]
            for edge in (orders?["edges"] as? [[String: Any]]) ?? [] {
                guard let node = edge["node"] as? [String: Any], let created = iso(node["createdAt"] as? String),
                      node["cancelledAt"] as? String == nil,
                      ["PAID", "PARTIALLY_REFUNDED", "REFUNDED", "PARTIALLY_PAID"].contains(node["displayFinancialStatus"] as? String ?? "")
                else { continue }
                let money = (node["totalPriceSet"] as? [String: Any])?["shopMoney"] as? [String: Any]
                let refunded = num(((node["totalRefundedSet"] as? [String: Any])?["shopMoney"] as? [String: Any])?["amount"])
                let net = num(money?["amount"]) - refunded
                let usd = await Rates.shared.usd(net, (money?["currencyCode"] as? String) ?? "USD", session: session) ?? 0
                items.append((created, ["revenue": usd, "sales": 1]))
            }
            let page = orders?["pageInfo"] as? [String: Any]
            guard (page?["hasNextPage"] as? Bool) == true, let end = page?["endCursor"] as? String else { break }
            cursor = end
        }
        return summed(items, start: start, keys: ["revenue", "sales"])
    }

    // MARK: Paddle

    /// Completed transactions (Paddle Billing); amounts come in the currency's smallest unit.
    static func paddle(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let base = i.field("environment").lowercased().hasPrefix("sand") ? "https://sandbox-api.paddle.com" : "https://api.paddle.com"
        var comps = URLComponents(string: base + "/transactions")!
        comps.queryItems = [.init(name: "status", value: "completed"), .init(name: "per_page", value: "200"),
                            .init(name: "created_at[GTE]", value: isoString(start.startOfDay))]
        var next: URL? = comps.url
        var items: [(Date, [String: Double])] = []
        for _ in 0..<50 {
            guard let url = next else { break }
            let obj = try json(try await load(request(url, headers: ["Authorization": "Bearer \(secret)"]), session: session)) as? [String: Any]
            for t in (obj?["data"] as? [[String: Any]]) ?? [] {
                guard let created = iso((t["billed_at"] as? String) ?? (t["created_at"] as? String)) else { continue }
                let totals = (t["details"] as? [String: Any])?["totals"] as? [String: Any]
                let amount = num(totals?["total"]) / 100
                let usd = await Rates.shared.usd(amount, (t["currency_code"] as? String) ?? "USD", session: session) ?? 0
                items.append((created, ["revenue": usd, "sales": 1]))
            }
            let pg = (obj?["meta"] as? [String: Any])?["pagination"] as? [String: Any]
            next = (pg?["has_more"] as? Bool) == true ? (pg?["next"] as? String).flatMap(URL.init(string:)) : nil
        }
        return summed(items, start: start, keys: ["revenue", "sales"])
    }

    // MARK: Polar

    static func polar(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        page: for n in 1...50 {
            var comps = URLComponents(string: "https://api.polar.sh/v1/orders/")!
            comps.queryItems = [.init(name: "limit", value: "100"), .init(name: "page", value: String(n)), .init(name: "sorting", value: "-created_at")]
            if !i.field("organization").isEmpty { comps.queryItems?.append(.init(name: "organization_id", value: i.field("organization"))) }
            let obj = try json(try await load(request(comps.url!, headers: ["Authorization": "Bearer \(secret)", "Accept": "application/json"]), session: session)) as? [String: Any]
            let rows = (obj?["items"] as? [[String: Any]]) ?? []
            for o in rows {
                guard let created = iso(o["created_at"] as? String) else { continue }
                if created < start.startOfDay { break page }
                let status = o["status"] as? String ?? "paid"
                guard status != "pending", status != "refunded", (o["paid"] as? Bool) != false else { continue }
                let gross = o["net_amount"] != nil ? num(o["net_amount"]) : num(o["amount"])
                let cents = gross - num(o["refunded_amount"])
                let usd = await Rates.shared.usd(cents / 100, (o["currency"] as? String) ?? "usd", session: session) ?? 0
                items.append((created, ["revenue": usd, "sales": 1]))
            }
            let maxPage = ((obj?["pagination"] as? [String: Any])?["max_page"] as? Int) ?? n
            if rows.isEmpty || n >= maxPage { break }
        }
        return summed(items, start: start, keys: ["revenue", "sales"])
    }

    // MARK: Fathom

    static func fathom(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var comps = URLComponents(string: "https://api.usefathom.com/v1/aggregations")!
        comps.queryItems = [
            .init(name: "entity", value: "pageview"), .init(name: "entity_id", value: i.field("site")),
            .init(name: "aggregates", value: "visits,pageviews"), .init(name: "date_grouping", value: "day"),
            .init(name: "date_from", value: DayKey.string(start) + " 00:00:00"), .init(name: "timezone", value: TimeZone.current.identifier),
        ]
        let obj = try json(try await load(request(comps.url!, headers: ["Authorization": "Bearer \(secret)"]), session: session))
        var items: [(Date, [String: Double])] = []
        for row in (obj as? [[String: Any]]) ?? [] {
            guard let day = iso((row["date"] as? String).map { $0.count == 10 ? $0 + " 12:00:00" : $0 }) else { continue }
            items.append((day, ["visits": num(row["visits"]), "pageviews": num(row["pageviews"])]))
        }
        return summed(items, start: start, keys: ["visits", "pageviews"])
    }

    // MARK: PostHog

    /// Daily unique people with a pageview, and pageviews, through a HogQL query.
    static func posthog(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        let hostField = i.field("host")
        let base = hostField.isEmpty ? "https://us.posthog.com" : (hostField.hasPrefix("http") ? hostField : "https://" + hostField)
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/projects/\(i.field("projectID"))/query/") else {
            throw MetricsError.invalidURL
        }
        let hogql = "SELECT toDate(timestamp) AS d, count(DISTINCT person_id), count() FROM events "
            + "WHERE event = '$pageview' AND timestamp >= toDateTime('\(DayKey.string(start)) 00:00:00') GROUP BY d ORDER BY d"
        let body = try JSONSerialization.data(withJSONObject: ["query": ["kind": "HogQLQuery", "query": hogql]])
        let req = request(url, method: "POST", headers: ["Authorization": "Bearer \(secret)", "Content-Type": "application/json"], body: body)
        let obj = try json(try await load(req, session: session)) as? [String: Any]
        var items: [(Date, [String: Double])] = []
        for row in (obj?["results"] as? [[Any]]) ?? [] {
            guard row.count >= 3, let day = iso((row[0] as? String).map { String($0.prefix(10)) + " 12:00:00" }) else { continue }
            items.append((day, ["visits": num(row[1]), "pageviews": num(row[2])]))
        }
        return summed(items, start: start, keys: ["visits", "pageviews"])
    }

    // MARK: Simple Analytics

    static func simpleAnalytics(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var comps = URLComponents(string: "https://simpleanalytics.com/\(host(i.field("site"))).json")
        comps?.queryItems = [
            .init(name: "version", value: "6"), .init(name: "fields", value: "histogram"),
            .init(name: "start", value: DayKey.string(start)), .init(name: "end", value: DayKey.string(.now)),
            .init(name: "timezone", value: TimeZone.current.identifier),
        ]
        guard let url = comps?.url else { throw MetricsError.invalidURL }
        let req = request(url, headers: ["Api-Key": secret, "User-Id": i.field("userID"), "Content-Type": "application/json"])
        let obj = try json(try await load(req, session: session)) as? [String: Any]
        var items: [(Date, [String: Double])] = []
        for row in (obj?["histogram"] as? [[String: Any]]) ?? [] {
            guard let day = iso((row["date"] as? String).map { String($0.prefix(10)) + " 12:00:00" }) else { continue }
            items.append((day, ["visits": num(row["visitors"]), "pageviews": num(row["pageviews"])]))
        }
        return summed(items, start: start, keys: ["visits", "pageviews"])
    }

    // MARK: Vercel and Netlify

    /// Successful deploys since the start: the building-phase pulse a web project has.
    static func vercel(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        var until: Int?
        for _ in 0..<30 {
            var comps = URLComponents(string: "https://api.vercel.com/v6/deployments")!
            comps.queryItems = [.init(name: "projectId", value: i.field("projectID")), .init(name: "limit", value: "100"),
                                .init(name: "since", value: String(Int(start.startOfDay.timeIntervalSince1970 * 1000)))]
            if !i.field("teamID").isEmpty { comps.queryItems?.append(.init(name: "teamId", value: i.field("teamID"))) }
            if let until { comps.queryItems?.append(.init(name: "until", value: String(until))) }
            let obj = try json(try await load(request(comps.url!, headers: ["Authorization": "Bearer \(secret)"]), session: session)) as? [String: Any]
            for d in (obj?["deployments"] as? [[String: Any]]) ?? [] {
                let state = (d["state"] as? String) ?? (d["readyState"] as? String) ?? ""
                guard state == "READY" else { continue }
                let ms = num(d["created"])
                items.append((Date(timeIntervalSince1970: ms / 1000), ["deploys": 1]))
            }
            guard let next = (obj?["pagination"] as? [String: Any])?["next"] as? Int else { break }
            until = next
        }
        return summed(items, start: start, keys: ["deploys"])
    }

    static func netlify(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        page: for n in 1...30 {
            guard let url = URL(string: "https://api.netlify.com/api/v1/sites/\(i.field("site"))/deploys?per_page=100&page=\(n)") else {
                throw MetricsError.invalidURL
            }
            let rows = (try json(try await load(request(url, headers: ["Authorization": "Bearer \(secret)"]), session: session)) as? [[String: Any]]) ?? []
            for d in rows {
                guard let created = iso(d["created_at"] as? String) else { continue }
                if created < start.startOfDay { break page }
                if (d["state"] as? String) == "ready" { items.append((created, ["deploys": 1])) }
            }
            if rows.count < 100 { break }
        }
        return summed(items, start: start, keys: ["deploys"])
    }

    // MARK: Newsletters

    static func kit(secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        var cursor: String?
        for _ in 0..<50 {
            var comps = URLComponents(string: "https://api.kit.com/v4/subscribers")!
            comps.queryItems = [.init(name: "created_after", value: isoString(start.startOfDay)), .init(name: "per_page", value: "1000"),
                                .init(name: "status", value: "active")]
            if let cursor { comps.queryItems?.append(.init(name: "after", value: cursor)) }
            let obj = try json(try await load(request(comps.url!, headers: ["X-Kit-Api-Key": secret, "Accept": "application/json"]), session: session)) as? [String: Any]
            for sub in (obj?["subscribers"] as? [[String: Any]]) ?? [] {
                if let created = iso(sub["created_at"] as? String) { items.append((created, ["new_subscribers": 1])) }
            }
            let pg = obj?["pagination"] as? [String: Any]
            guard (pg?["has_next_page"] as? Bool) == true, let end = pg?["end_cursor"] as? String else { break }
            cursor = end
        }
        return summed(items, start: start, keys: ["new_subscribers"])
    }

    static func buttondown(secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var comps = URLComponents(string: "https://api.buttondown.com/v1/subscribers")!
        comps.queryItems = [.init(name: "creation_date__start", value: DayKey.string(start)), .init(name: "type", value: "regular")]
        var next: URL? = comps.url
        var items: [(Date, [String: Double])] = []
        for _ in 0..<50 {
            guard let url = next else { break }
            let obj = try json(try await load(request(url, headers: ["Authorization": "Token \(secret)"]), session: session)) as? [String: Any]
            for sub in (obj?["results"] as? [[String: Any]]) ?? [] {
                if let created = iso(sub["creation_date"] as? String), created >= start.startOfDay { items.append((created, ["new_subscribers": 1])) }
            }
            next = (obj?["next"] as? String).flatMap(URL.init(string:))
        }
        return summed(items, start: start, keys: ["new_subscribers"])
    }

    static func beehiiv(_ i: Integration, secret: String, start: Date, session: URLSession) async throws -> SourceResult {
        var items: [(Date, [String: Double])] = []
        page: for n in 1...50 {
            var comps = URLComponents(string: "https://api.beehiiv.com/v2/publications/\(i.field("publication"))/subscriptions")!
            comps.queryItems = [.init(name: "limit", value: "100"), .init(name: "page", value: String(n)), .init(name: "status", value: "active"),
                                .init(name: "order_by", value: "created"), .init(name: "direction", value: "desc")]
            let obj = try json(try await load(request(comps.url!, headers: ["Authorization": "Bearer \(secret)"]), session: session)) as? [String: Any]
            let rows = (obj?["data"] as? [[String: Any]]) ?? []
            for sub in rows {
                let created = Date(timeIntervalSince1970: num(sub["created"]))
                if created < start.startOfDay { break page }
                items.append((created, ["new_subscribers": 1]))
            }
            if rows.isEmpty || n >= ((obj?["total_pages"] as? Int) ?? n) { break }
        }
        return summed(items, start: start, keys: ["new_subscribers"])
    }

    // MARK: Public sources (no key)

    static func npm(_ i: Integration, start: Date, session: URLSession) async throws -> SourceResult {
        let pkg = i.field("package")
        guard !pkg.isEmpty, let url = URL(string: "https://api.npmjs.org/downloads/range/\(DayKey.string(start)):\(DayKey.string(.now))/\(pkg)") else {
            throw MetricsError.invalidURL
        }
        let obj = try json(try await load(request(url), session: session)) as? [String: Any]
        var items: [(Date, [String: Double])] = []
        for row in (obj?["downloads"] as? [[String: Any]]) ?? [] {
            guard let day = iso((row["day"] as? String).map { $0 + " 12:00:00" }) else { continue }
            items.append((day, ["downloads": num(row["downloads"])]))
        }
        return summed(items, start: start, keys: ["downloads"])
    }

    /// Points on stories linking to the site, posted since the start (Hacker News search by Algolia).
    static func hackerNews(_ i: Integration, start: Date, session: URLSession) async throws -> SourceResult {
        var comps = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        comps.queryItems = [.init(name: "query", value: host(i.field("url"))), .init(name: "restrictSearchableAttributes", value: "url"),
                            .init(name: "tags", value: "story"), .init(name: "hitsPerPage", value: "100"),
                            .init(name: "numericFilters", value: "created_at_i>=\(Int(start.startOfDay.timeIntervalSince1970))")]
        let obj = try json(try await load(request(comps.url!), session: session)) as? [String: Any]
        let hits = (obj?["hits"] as? [[String: Any]]) ?? []
        var r = SourceResult()
        r.totals["hn_points"] = hits.reduce(0) { $0 + num($1["points"]) }
        r.totals["hn_comments"] = hits.reduce(0) { $0 + num($1["num_comments"]) }
        return r
    }

    static func productHunt(_ i: Integration, secret: String, session: URLSession) async throws -> SourceResult {
        let slug = i.field("slug").split(separator: "/").last.map(String.init)?.split(separator: "?").first.map(String.init) ?? ""
        guard !slug.isEmpty, let url = URL(string: "https://api.producthunt.com/v2/api/graphql") else { throw MetricsError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: ["query": "query { post(slug: \"\(slug)\") { votesCount commentsCount } }"])
        let req = request(url, method: "POST", headers: ["Authorization": "Bearer \(secret)", "Content-Type": "application/json"], body: body)
        let obj = try json(try await load(req, session: session)) as? [String: Any]
        guard let post = (obj?["data"] as? [String: Any])?["post"] as? [String: Any] else {
            throw MetricsError.badPayload("no launch found for \(slug)")
        }
        var r = SourceResult()
        r.totals["upvotes"] = num(post["votesCount"])
        r.totals["ph_comments"] = num(post["commentsCount"])
        return r
    }

    static func bluesky(_ i: Integration, session: URLSession) async throws -> SourceResult {
        var handle = i.field("handle")
        if handle.hasPrefix("@") { handle.removeFirst() }
        var comps = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile")!
        comps.queryItems = [.init(name: "actor", value: handle)]
        let obj = try json(try await load(request(comps.url!), session: session)) as? [String: Any]
        var r = SourceResult()
        r.totals["followers"] = num(obj?["followersCount"])
        return r
    }

    /// Totals and complete daily steps from a list of dated amounts.
    static func summed(_ items: [(Date, [String: Double])], start: Date, keys: Set<String>) -> SourceResult {
        var r = SourceResult()
        r.daily = dailyFrom(items, start: start, keys: keys)
        r.dailyKeys = keys
        for k in keys { r.totals[k] = items.filter { $0.0 >= start.startOfDay }.reduce(0) { $0 + ($1.1[k] ?? 0) } }
        if let rev = r.totals["revenue"] { r.totals["revenue"] = (rev * 100).rounded() / 100 }
        return r
    }
}

// MARK: - gzip (sales reports arrive compressed)

nonisolated enum Gzip {
    /// Inflates a gzip file; nil if it isn't one.
    static func inflate(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var i = 10
        if flags & 0x04 != 0 { guard bytes.count > i + 2 else { return nil }; i += 2 + Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        if flags & 0x08 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 }
        if flags & 0x10 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 }
        if flags & 0x02 != 0 { i += 2 }
        guard i < bytes.count - 8 else { return nil }
        let deflated = Array(bytes[i..<(bytes.count - 8)])
        let size = Int(bytes[bytes.count - 4]) | Int(bytes[bytes.count - 3]) << 8 | Int(bytes[bytes.count - 2]) << 16 | Int(bytes[bytes.count - 1]) << 24
        var capacity = max(size, deflated.count * 4, 1024)
        for _ in 0..<4 {
            var out = [UInt8](repeating: 0, count: capacity)
            let n = compression_decode_buffer(&out, capacity, deflated, deflated.count, nil, COMPRESSION_ZLIB)
            if n > 0 && n < capacity { return Data(out[0..<n]) }
            capacity *= 4
        }
        return nil
    }
}
