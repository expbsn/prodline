import Foundation

// MARK: - Any number, by key
//
// The three built-in metrics (visits, social views, revenue) plus whatever integrations and endpoints
// report (downloads, MRR, deploys, followers…). Screens show the numbers a project actually gets, and
// when there are more than three, the three the user picked.

nonisolated enum Stat {
    static let revenue = MetricKey.revenue.rawValue

    static func title(_ key: String) -> String {
        MetricKey(rawValue: key)?.title ?? IntegrationMetric.title(key)
    }

    static func format(_ key: String, _ v: Double) -> String {
        key == revenue ? MetricKey.money(v) : IntegrationMetric.format(key, v)
    }

    static func symbol(_ key: String) -> String {
        if let k = MetricKey(rawValue: key) { return k.symbol }
        return switch key {
        case "downloads": "arrow.down.circle.fill"
        case "sales": "cart.fill"
        case "mrr", "arr": "repeat.circle.fill"
        case "active_subscriptions": "person.crop.circle.badge.checkmark"
        case "active_trials": "hourglass"
        case "new_subscribers", "subscribers": "envelope.fill"
        case "followers": "person.2.fill"
        case "deploys": "arrow.up.circle.fill"
        case "pageviews": "doc.text.fill"
        case "rating": "star.fill"
        case "ratings": "star.bubble.fill"
        case "upvotes": "arrowtriangle.up.fill"
        case "hn_points": "flame.fill"
        case "videos_posted": "play.rectangle.fill"
        case "app_store_proceeds": "banknote.fill"
        default: "number"
        }
    }

    /// Which numbers come first when nothing's been picked.
    static let priority = [
        "revenue", "downloads", "visits", "social_views", "mrr", "sales", "active_subscriptions", "new_subscribers",
        "followers", "upvotes", "hn_points", "deploys", "pageviews", "subscribers", "rating", "videos_posted",
        "active_trials", "ratings", "hn_comments", "ph_comments", "app_store_proceeds",
    ]

    static func sorted(_ keys: Set<String>) -> [String] {
        keys.sorted { a, b in
            let ia = priority.firstIndex(of: a) ?? Int.max, ib = priority.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a < b
        }
    }

    /// Ratings don't add up across projects; everything else does.
    static func isAverage(_ key: String) -> Bool { key == "rating" }

    /// The keys to show: all of them up to three, otherwise the picked ones (topped up in priority order).
    static func shown(available: [String], picked: [String]) -> [String] {
        guard available.count > 3 else { return available }
        var out: [String] = []
        for k in picked + available where out.count < 3 && available.contains(k) && !out.contains(k) { out.append(k) }
        return out
    }

    /// `picked` with `old` swapped for `new`, kept in the shown order.
    static func swap(_ old: String, for new: String, shown: [String]) -> [String] {
        shown.map { $0 == old ? new : $0 }
    }
}

extension IntegrationKind {
    /// The numbers this service reports.
    nonisolated var keys: [String] {
        switch self {
        case .appStore: ["downloads", "revenue", "rating", "ratings", "app_store_proceeds"]
        case .revenueCat: ["revenue", "mrr", "active_subscriptions", "active_trials"]
        case .stripe, .lemonSqueezy, .gumroad, .shopify, .paddle, .polar: ["revenue", "sales"]
        case .plausible, .umami, .fathom, .posthog, .simpleAnalytics: ["visits", "pageviews"]
        case .youtube: ["social_views", "videos_posted", "subscribers"]
        case .vercel, .netlify: ["deploys"]
        case .kit, .buttondown, .beehiiv: ["new_subscribers"]
        case .npm: ["downloads"]
        case .hackerNews: ["hn_points", "hn_comments"]
        case .productHunt: ["upvotes", "ph_comments"]
        case .bluesky: ["followers"]
        }
    }
}

extension MetricSnapshot {
    func value(_ key: String) -> Double {
        MetricKey(rawValue: key).map(value) ?? extras[key] ?? 0
    }
}

extension Project {
    /// The numbers picked for this project's tiles, when it has more than three.
    var pickedMetrics: [String] {
        get { trackedMetricsRaw.split(separator: ",").map(String.init) }
        set { trackedMetricsRaw = newValue.joined(separator: ",") }
    }
}

extension DataRefresher {
    func value(_ key: String, for project: Project) -> Double? {
        if let k = MetricKey(rawValue: key) { return value(k, for: project) }
        return extras(for: project).first { $0.key == key }?.value
    }

    /// Every number this project gets: from its integrations, plus whatever its endpoint (or the sample
    /// data) reports. Without either, the three built-in ones.
    func availableMetrics(for project: Project) -> [String] {
        var keys = Set(project.integrations.flatMap(\.kind.keys))
        keys.formUnion(extras(for: project).map(\.key))
        if !project.endpoint.trimmingCharacters(in: .whitespaces).isEmpty || project.integrations.isEmpty {
            keys.formUnion(MetricKey.allCases.map(\.rawValue))
        }
        return Stat.sorted(keys)
    }

    func shownMetrics(for project: Project) -> [String] {
        Stat.shown(available: availableMetrics(for: project), picked: project.pickedMetrics)
    }
}
