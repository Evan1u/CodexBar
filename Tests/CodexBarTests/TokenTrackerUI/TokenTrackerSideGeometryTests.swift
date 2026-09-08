import AppKit
import Testing
@testable import CodexBar

@Suite("Token Tracker side geometry")
struct TokenTrackerSideGeometryTests {
    @Test
    func `rail uses the proportional no scroll surface metrics`() throws {
        let screen = self.screen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            visible: CGRect(x: 0, y: 0, width: 1200, height: 800))

        #expect(TokenTrackerSideGeometry.railWidth(for: .compact) == 52)
        #expect(TokenTrackerSideGeometry.railWidth(for: .standard) == 56)
        #expect(TokenTrackerSideGeometry.railWidth(for: .wide) == 60)
        let one = try #require(TokenTrackerSideGeometry.providerSurfaceMetrics(
            providerCount: 1,
            size: .standard,
            on: screen))
        let three = try #require(TokenTrackerSideGeometry.providerSurfaceMetrics(
            providerCount: 3,
            size: .standard,
            on: screen))
        let four = try #require(TokenTrackerSideGeometry.providerSurfaceMetrics(
            providerCount: 4,
            size: .standard,
            on: screen))

        #expect(abs(one.aspectRatio - 2.011951) < 0.001)
        #expect(abs(three.aspectRatio - 4.371951) < 0.001)
        #expect(abs(four.aspectRatio - 5.551951) < 0.001)
        #expect(abs(three.longAxis - 244.829268) < 0.001)
        #expect(abs(three.contentBandCenter(for: 0) - 56.334634) < 0.001)
        #expect(three.contentBandCenter(for: 1) == three.longAxis / 2)
        #expect(abs(three.contentBandCenter(for: 1) - three.contentBandCenter(for: 0) - 66.08) < 0.001)
        #expect(abs(TokenTrackerSideGeometry.railHeight(providerCount: 3, on: screen) - 244.829268) < 0.001)
    }

    @Test
    func `screen pointer maps to the matching visual provider slot`() throws {
        let metrics = try #require(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 3,
            preferredSlot: 64,
            availableLongAxis: 800))
        let panel = CGRect(x: 1136, y: 240, width: metrics.slot, height: metrics.longAxis)

        for index in 0..<metrics.providerCount {
            let screenPoint = CGPoint(
                x: panel.midX,
                y: panel.maxY - metrics.contentBandCenter(for: index))
            #expect(TokenTrackerSideGeometry.providerIndex(
                at: screenPoint,
                in: panel,
                metrics: metrics) == index)
        }
        #expect(TokenTrackerSideGeometry.providerIndex(
            at: CGPoint(x: panel.midX, y: panel.minY + 8),
            in: panel,
            metrics: metrics) == nil)

        let handle = CGRect(x: panel.minX, y: panel.minY + 4, width: 22, height: 58)
        #expect(TokenTrackerSideGeometry.containsExpandedInteractiveTarget(
            at: CGPoint(x: handle.midX, y: panel.minY + 8),
            in: panel,
            metrics: metrics,
            handleFrame: handle))
        #expect(!TokenTrackerSideGeometry.containsExpandedInteractiveTarget(
            at: CGPoint(x: panel.midX, y: panel.maxY - 178),
            in: panel,
            metrics: metrics,
            handleFrame: handle))
    }

    @Test
    func `left and right frames anchor to visible edges and restore normalized y`() {
        let screen = self.screen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            visible: CGRect(x: 20, y: 40, width: 1160, height: 820))
        let size = CGSize(width: 80, height: 420)
        let left = TokenTrackerSideGeometry.frame(size: size, on: screen, edge: .left, normalizedY: 0.25)
        let right = TokenTrackerSideGeometry.frame(size: size, on: screen, edge: .right, normalizedY: 0.25)

        #expect(left.minX == screen.visibleFrame.minX)
        #expect(right.maxX == screen.visibleFrame.maxX)
        #expect(left.minY == 140)
        #expect(TokenTrackerSideGeometry.normalizedY(for: left, on: screen) == 0.25)
        #expect(TokenTrackerSideGeometry.normalizedY(for: right, on: screen) == 0.25)
    }

    @Test
    func `dimensions and y clamp inside visible frame`() {
        let screen = self.screen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visible: CGRect(x: 0, y: 30, width: 760, height: 520))
        let frame = TokenTrackerSideGeometry.frame(
            size: CGSize(width: 1000, height: 900),
            on: screen,
            edge: .right,
            normalizedY: 4)

        #expect(frame == screen.visibleFrame)
        #expect(TokenTrackerSideGeometry.normalizedY(for: frame, on: screen) == 0)
    }

    @Test
    func `snap chooses screen by window center and nearest visible edge`() throws {
        let leftScreen = self.screen(
            id: 1,
            persistentID: "left-screen",
            frame: CGRect(x: -1000, y: 0, width: 1000, height: 800),
            visible: CGRect(x: -1000, y: 20, width: 1000, height: 740))
        let rightScreen = self.screen(
            id: 2,
            persistentID: "right-screen",
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            visible: CGRect(x: 0, y: 40, width: 1180, height: 820))
        let panel = CGRect(x: 1030, y: 200, width: 80, height: 420)

        let target = try #require(TokenTrackerSideGeometry.snapTarget(
            for: panel,
            screens: [leftScreen, rightScreen]))
        #expect(target.screen == rightScreen)
        #expect(target.edge == .right)
        #expect(target.normalizedY == 0.4)
    }

    @Test
    func `detail panel opens inward without changing rail frame`() {
        let screen = self.screen(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            visible: CGRect(x: 20, y: 40, width: 1160, height: 820))
        let railSize = CGSize(width: 80, height: 204)
        let leftRail = TokenTrackerSideGeometry.frame(size: railSize, on: screen, edge: .left, normalizedY: 0.5)
        let rightRail = TokenTrackerSideGeometry.frame(size: railSize, on: screen, edge: .right, normalizedY: 0.5)
        let leftDetail = TokenTrackerSideGeometry.detailFrame(
            size: CGSize(width: 360, height: 410),
            adjacentTo: leftRail,
            on: screen,
            edge: .left)
        let rightDetail = TokenTrackerSideGeometry.detailFrame(
            size: CGSize(width: 360, height: 410),
            adjacentTo: rightRail,
            on: screen,
            edge: .right)

        #expect(leftDetail.minX == leftRail.maxX)
        #expect(rightDetail.maxX == rightRail.minX)
        #expect(!leftDetail.intersects(leftRail))
        #expect(!rightDetail.intersects(rightRail))
        #expect(leftRail == TokenTrackerSideGeometry.frame(
            size: railSize,
            on: screen,
            edge: .left,
            normalizedY: 0.5))
    }

    @Test
    func `side screen restore falls back through mouse main and first`() {
        let first = self.screen(id: 1, persistentID: "first", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let second = self.screen(
            id: 2,
            persistentID: "second",
            frame: CGRect(x: 800, y: 0, width: 800, height: 600))

        #expect(TokenTrackerSideScreenResolver.resolve(
            screens: [first, second],
            savedPersistentID: "second",
            mouseLocation: CGPoint(x: 10, y: 10),
            mainDisplayID: 1) == second)
        #expect(TokenTrackerSideScreenResolver.resolve(
            screens: [first, second],
            savedPersistentID: "missing",
            mouseLocation: CGPoint(x: 900, y: 10),
            mainDisplayID: 1) == second)
        #expect(TokenTrackerSideScreenResolver.resolve(
            screens: [first, second],
            savedPersistentID: nil,
            mouseLocation: CGPoint(x: 9000, y: 10),
            mainDisplayID: 1) == first)
        #expect(TokenTrackerSideScreenResolver.resolve(
            screens: [],
            savedPersistentID: nil,
            mouseLocation: nil,
            mainDisplayID: nil) == nil)
    }

    private func screen(
        id: CGDirectDisplayID,
        persistentID: String? = nil,
        frame: CGRect,
        visible: CGRect? = nil) -> TokenTrackerScreenSnapshot
    {
        TokenTrackerScreenSnapshot(
            runtimeDisplayID: id,
            persistentID: persistentID,
            frame: frame,
            visibleFrame: visible ?? frame)
    }
}
