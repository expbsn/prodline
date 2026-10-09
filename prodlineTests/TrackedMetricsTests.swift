import Foundation
import Testing
@testable import prodline

@Suite("Tracked metrics")
struct TrackedMetricsTests {
    @Test func upToThreeShowsEverything() {
        #expect(Stat.shown(available: ["revenue", "sales"], picked: ["visits"]) == ["revenue", "sales"])
    }

    @Test func moreThanThreeUsesThePickThenPriority() {
        let available = Stat.sorted(["sales", "revenue", "downloads", "deploys", "visits"])
        #expect(available == ["revenue", "downloads", "visits", "sales", "deploys"])
        #expect(Stat.shown(available: available, picked: []) == ["revenue", "downloads", "visits"])
        #expect(Stat.shown(available: available, picked: ["deploys", "gone", "deploys"]) == ["deploys", "revenue", "downloads"])
    }

    @Test func swappingKeepsTheSlot() {
        #expect(Stat.swap("downloads", for: "deploys", shown: ["revenue", "downloads", "visits"]) == ["revenue", "deploys", "visits"])
    }

    @Test func integrationsDecideTheNumbers() {
        #expect(IntegrationKind.vercel.keys == ["deploys"])
        #expect(Set(IntegrationKind.appStore.keys).isSuperset(of: ["downloads", "revenue"]))
        #expect(Stat.title("deploys") == "Deploys")
        #expect(Stat.format("revenue", 12) == "$12.00")
    }
}
