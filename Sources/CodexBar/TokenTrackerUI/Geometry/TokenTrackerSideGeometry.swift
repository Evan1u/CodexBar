import AppKit

struct TokenTrackerSideSnapTarget: Equatable, Sendable {
    let screen: TokenTrackerScreenSnapshot
    let edge: TokenTrackerHorizontalEdge
    let normalizedY: Double
}

enum TokenTrackerSideScreenResolver {
    static func resolve(
        screens: [TokenTrackerScreenSnapshot],
        savedPersistentID: String?,
        mouseLocation: CGPoint?,
        mainDisplayID: CGDirectDisplayID?) -> TokenTrackerScreenSnapshot?
    {
        if let savedPersistentID,
           let saved = screens.first(where: { $0.persistentID == savedPersistentID })
        {
            return saved
        }
        if let mouseLocation,
           let mouseScreen = screens.first(where: { $0.frame.contains(mouseLocation) })
        {
            return mouseScreen
        }
        if let mainDisplayID,
           let main = screens.first(where: { $0.runtimeDisplayID == mainDisplayID })
        {
            return main
        }
        return screens.first
    }
}

enum TokenTrackerSideGeometry {
    static let handleSize = CGSize(width: 22, height: 58)
    static let visualHandleWidth: CGFloat = 6
    static let visualHandleOuterInset: CGFloat = 6
    static let railWidthRange: ClosedRange<CGFloat> = 52...60

    static func railWidth(for size: TokenTrackerSurfaceSize) -> CGFloat {
        switch size {
        case .compact: 52
        case .standard: 56
        case .wide: 60
        }
    }

    static func providerSurfaceMetrics(
        providerCount: Int,
        size: TokenTrackerSurfaceSize,
        on screen: TokenTrackerScreenSnapshot,
        backingScaleFactor: CGFloat = 2) -> TokenTrackerProviderSurfaceMetrics?
    {
        TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: providerCount,
            preferredSlot: self.railWidth(for: size),
            availableLongAxis: max(
                screen.visibleFrame.height - TokenTrackerProviderSurfaceMetrics.safetyInset,
                0),
            backingScaleFactor: backingScaleFactor)
    }

    static func railHeight(providerCount: Int, on screen: TokenTrackerScreenSnapshot) -> CGFloat {
        self.providerSurfaceMetrics(providerCount: providerCount, size: .standard, on: screen)?.longAxis
            ?? self.handleSize.height
    }

    /// Returns the visual Provider-slot index under a screen-space pointer.
    /// SwiftUI uses a top-left local Y origin, whereas AppKit screen coordinates
    /// are bottom-left, so this conversion remains the single hit-test truth.
    static func providerIndex(
        at screenPoint: CGPoint,
        in panelFrame: CGRect,
        metrics: TokenTrackerProviderSurfaceMetrics) -> Int?
    {
        guard panelFrame.contains(screenPoint) else { return nil }
        let localPoint = CGPoint(
            x: screenPoint.x - panelFrame.minX,
            y: panelFrame.maxY - screenPoint.y)
        guard localPoint.x >= 0, localPoint.x <= metrics.slot else { return nil }

        for index in 0..<metrics.providerCount {
            let center = metrics.contentBandCenter(for: index)
            let slotFrame = CGRect(
                x: 0,
                y: center - metrics.slot / 2,
                width: metrics.slot,
                height: metrics.slot)
            if slotFrame.contains(localPoint) {
                return index
            }
        }
        return nil
    }

    static func containsExpandedInteractiveTarget(
        at screenPoint: CGPoint,
        in panelFrame: CGRect,
        metrics: TokenTrackerProviderSurfaceMetrics,
        handleFrame: CGRect) -> Bool
    {
        self.providerIndex(at: screenPoint, in: panelFrame, metrics: metrics) != nil
            || handleFrame.contains(screenPoint)
    }

    static func frame(
        size requestedSize: CGSize,
        on screen: TokenTrackerScreenSnapshot,
        edge: TokenTrackerHorizontalEdge,
        normalizedY: Double) -> CGRect
    {
        let visible = screen.visibleFrame
        let width = min(max(requestedSize.width, 0), max(visible.width, 0))
        let height = min(max(requestedSize.height, 0), max(visible.height, 0))
        let x = switch edge {
        case .left: visible.minX
        case .right: visible.maxX - width
        }
        let usableY = max(visible.height - height, 0)
        let fraction = min(1, max(0, normalizedY.isFinite ? normalizedY : 0.5))
        return CGRect(
            x: x,
            y: visible.minY + CGFloat(fraction) * usableY,
            width: width,
            height: height)
    }

    static func normalizedY(for panelFrame: CGRect, on screen: TokenTrackerScreenSnapshot) -> Double {
        let usableY = max(screen.visibleFrame.height - panelFrame.height, 0)
        guard usableY > 0 else { return 0 }
        return Double(min(1, max(0, (panelFrame.minY - screen.visibleFrame.minY) / usableY)))
    }

    static func detailFrame(
        size requestedSize: CGSize,
        adjacentTo railFrame: CGRect,
        on screen: TokenTrackerScreenSnapshot,
        edge: TokenTrackerHorizontalEdge) -> CGRect
    {
        let visible = screen.visibleFrame
        let availableWidth = max(visible.width - railFrame.width, 0)
        let width = min(max(requestedSize.width, 0), availableWidth)
        let height = min(max(requestedSize.height, 0), max(visible.height, 0))
        let x = switch edge {
        case .left: min(railFrame.maxX, visible.maxX - width)
        case .right: max(railFrame.minX - width, visible.minX)
        }
        let maximumY = max(visible.minY, visible.maxY - height)
        let y = min(max(railFrame.minY, visible.minY), maximumY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func snapTarget(
        for panelFrame: CGRect,
        screens: [TokenTrackerScreenSnapshot]) -> TokenTrackerSideSnapTarget?
    {
        guard let screen = self.screen(
            containingOrNearestTo: CGPoint(x: panelFrame.midX, y: panelFrame.midY),
            screens: screens)
        else { return nil }
        let leftDistance = abs(panelFrame.midX - screen.visibleFrame.minX)
        let rightDistance = abs(screen.visibleFrame.maxX - panelFrame.midX)
        let edge: TokenTrackerHorizontalEdge = leftDistance <= rightDistance ? .left : .right
        return TokenTrackerSideSnapTarget(
            screen: screen,
            edge: edge,
            normalizedY: self.normalizedY(for: panelFrame, on: screen))
    }

    private static func screen(
        containingOrNearestTo point: CGPoint,
        screens: [TokenTrackerScreenSnapshot]) -> TokenTrackerScreenSnapshot?
    {
        if let containing = screens.first(where: { $0.frame.contains(point) }) {
            return containing
        }
        return screens.min { lhs, rhs in
            self.squaredDistance(from: point, to: lhs.frame) < self.squaredDistance(from: point, to: rhs.frame)
        }
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
