import AppKit
import Testing
@testable import CodexBar

@Suite("Token Tracker panel factory")
@MainActor
struct TokenTrackerPanelFactoryTests {
    @Test
    func `shell panel is nonactivating and space aware`() {
        let panel = TokenTrackerPanelFactory.makeShellPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1))
        defer { panel.close() }

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .statusBar)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.acceptsFirstResponder == false)
        #expect(panel.ignoresMouseEvents)
    }

    @Test
    func `side panel receives drag hover and keyboard events without eager activation`() {
        let panel = TokenTrackerPanelFactory.makeSidePanel(
            contentRect: NSRect(x: 0, y: 0, width: 22, height: 58))
        defer { panel.close() }

        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(panel.isKeyWindow == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.ignoresMouseEvents == false)
        #expect(panel.acceptsMouseMovedEvents)
        #expect(panel.isMovable == false)
        panel.orderFrontRegardless()
        #expect(panel.isKeyWindow == false)
    }

    @Test
    func `provider detail panel can become key only when interaction needs it`() {
        let panel = TokenTrackerPanelFactory.makeProviderDetailPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 410))
        defer { panel.close() }

        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey)
        #expect(panel.canBecomeMain == false)
        #expect(panel.acceptsFirstResponder)
        panel.orderFrontRegardless()
        #expect(panel.isKeyWindow == false)
    }
}
