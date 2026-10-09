import Foundation
import Testing
@testable import prodline

@MainActor
@Suite("What counts as a win")
struct SuccessFocusTests {
    @Test func focusBecomesTheDefaultTarget() {
        let profile = Profile()
        #expect(profile.defaultCriteria.isEmpty)

        profile.successFocus = .money
        profile.successTarget = SuccessFocus.money.defaultTarget
        #expect(profile.defaultCriteria.map(\.key) == ["revenue"])
        #expect(profile.defaultCriteria.first?.target == 500)

        profile.successFocus = .users
        profile.successTarget = 2000
        #expect(profile.defaultCriteria.map(\.key) == ["downloads"])
        #expect(profile.defaultCriteria.first?.target == 2000)
    }

    @Test func justShippingHasNoTargets() {
        let profile = Profile()
        profile.successFocus = .ship
        profile.successTarget = SuccessFocus.ship.defaultTarget
        #expect(profile.defaultCriteria.isEmpty)
        #expect(SuccessFocus.ship.presets.isEmpty)
    }
}
