import Foundation
import Testing
@testable import prodline

@MainActor
@Suite("Relay")
struct RelayTests {
    @Test func aProjectKeepsItsHookAndFindsItAgain() {
        let p = Project(name: "Kite", accentHex: 0x58CC02, startDate: .now, buildDays: 14, observeDays: 28)
        p.githubRepo = "kian/kite"
        let first = Relay.hook(for: p)
        #expect(first == Relay.hook(for: p))
        #expect(first.id.hasPrefix("hk_") && first.secret.hasPrefix("hs_"))
        #expect(Relay.project(forHook: first.id, in: [p]) === p)
        #expect(Relay.project(forHook: "hk_nope", in: [p]) == nil)
        Keychain.delete("relay-hook-" + p.id.uuidString)
    }

    @Test func webhookAddressFollowsTheRelaySetting() {
        let key = AppSettings.Key.relayURL
        UserDefaults.standard.set("https://relay.example.dev/", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let url = Relay.webhookURL(Relay.Hook(id: "hk_abc", secret: "hs_x"))
        #expect(url?.absoluteString == "https://relay.example.dev/github/hk_abc")
    }
}
