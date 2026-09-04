import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@Suite("Token Tracker provider anchor store")
@MainActor
struct TokenTrackerProviderAnchorStoreTests {
    @Test
    func `anchors are scoped by presentation mode and provider`() throws {
        let store = TokenTrackerProviderAnchorStore()
        let providerID = try #require(ProviderInstanceID(rawValue: "codex"))
        let sideAnchor = TokenTrackerProviderAnchor(
            tileFrame: CGRect(x: 10, y: 20, width: 52, height: 52),
            logoCenter: CGPoint(x: 36, y: 36),
            surfaceVisibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let bottomAnchor = TokenTrackerProviderAnchor(
            tileFrame: CGRect(x: 100, y: 200, width: 52, height: 52),
            logoCenter: CGPoint(x: 126, y: 216),
            surfaceVisibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))

        store.update(
            mode: .side,
            providerID: providerID,
            tileFrame: sideAnchor.tileFrame,
            logoCenter: sideAnchor.logoCenter,
            surfaceVisibleFrame: sideAnchor.surfaceVisibleFrame)
        store.update(
            mode: .bottom,
            providerID: providerID,
            tileFrame: bottomAnchor.tileFrame,
            logoCenter: bottomAnchor.logoCenter,
            surfaceVisibleFrame: bottomAnchor.surfaceVisibleFrame)

        #expect(store.anchor(mode: .side, providerID: providerID) == sideAnchor)
        #expect(store.anchor(mode: .bottom, providerID: providerID) == bottomAnchor)

        store.removeAll(for: .side)
        #expect(store.anchor(mode: .side, providerID: providerID) == nil)
        #expect(store.anchor(mode: .bottom, providerID: providerID) == bottomAnchor)
    }

}
