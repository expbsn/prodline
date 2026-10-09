import Foundation

/// What "it worked" means to the user, picked in onboarding. New projects start with a success target
/// built from it, which drives the keep / pivot / kill suggestion at the end of the observe phase.
enum SuccessFocus: String, CaseIterable, Identifiable {
    case money, users, audience, ship

    var id: String { rawValue }

    var title: String {
        switch self {
        case .money: "Make money"
        case .users: "Get users"
        case .audience: "Build an audience"
        case .ship: "Just ship it"
        }
    }

    var blurb: String {
        switch self {
        case .money: "Even $1 counts. Ramen profitable is a lifestyle."
        case .users: "Downloads and sign-ups. Real humans, ideally."
        case .audience: "Visits and views. Fame now, money later."
        case .ship: "No targets, no pressure. Done is the win."
        }
    }

    var symbol: String {
        switch self {
        case .money: "dollarsign"
        case .users: "person.2.fill"
        case .audience: "eye.fill"
        case .ship: "shippingbox.fill"
        }
    }

    var hex: Int {
        switch self {
        case .money: 0xFFC800
        case .users: 0x1CB0F6
        case .audience: 0xCE82FF
        case .ship: 0x58CC02
        }
    }

    /// The metric the target is set on; nil for "just ship it".
    var key: String? {
        switch self {
        case .money: MetricKey.revenue.rawValue
        case .users: "downloads"
        case .audience: MetricKey.visits.rawValue
        case .ship: nil
        }
    }

    /// Targets offered for the observe phase, small to ambitious.
    var presets: [Double] {
        switch self {
        case .money: [100, 500, 1000]
        case .users: [100, 500, 2000]
        case .audience: [1000, 5000, 20000]
        case .ship: []
        }
    }

    var defaultTarget: Double { presets.count > 1 ? presets[1] : 0 }

    func criteria(target: Double) -> [SuccessCriterion] {
        guard let key, target > 0 else { return [] }
        return [SuccessCriterion(key: key, target: target)]
    }
}

extension Profile {
    var successFocus: SuccessFocus? {
        get { SuccessFocus(rawValue: successFocusRaw) }
        set { successFocusRaw = newValue?.rawValue ?? "" }
    }

    /// Success targets a new project starts with.
    var defaultCriteria: [SuccessCriterion] { successFocus?.criteria(target: successTarget) ?? [] }
}
