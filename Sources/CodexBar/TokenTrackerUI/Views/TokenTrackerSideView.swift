import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct TokenTrackerSideView: View {
    @Bindable var projection: TokenTrackerProviderProjection
    @Bindable var interaction: TokenTrackerEdgeInteractionModel
    let anchorStore: TokenTrackerProviderAnchorStore
    let preferences: TokenTrackerPreferencesStore
    let openTokenTrackerSettings: @MainActor () -> Void
    let onDragEnded: @MainActor (CGRect) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if self.interaction.isProviderSurfaceVisible {
                self.expandedSurface
            } else {
                self.handle
            }
        }
        .foregroundStyle(.white)
    }

    private var expandedSurface: some View {
        GeometryReader { proxy in
            let shape = TokenTrackerEdgeProtrusionShape(attachmentEdge: self.attachmentEdge)
            ZStack {
                shape
                    .fill(.black.opacity(0.96))
                self.rail(in: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(.white.opacity(self.visualStyle.outlineOpacity), lineWidth: 1)
            }
        }
        .background {
            TokenTrackerNativeHoverRegion(
                assumePointerInside: self.interaction.isPointerInsideProviderSurface,
                onEnter: self.interaction.pointerEnteredProviderSurface,
                onExit: self.interaction.pointerExitedProviderSurface)
        }
    }

    private var handle: some View {
        ZStack(alignment: self.edge == .left ? .leading : .trailing) {
            Color.clear
            Capsule()
                .fill(.black.opacity(0.82))
                .overlay {
                    Capsule().stroke(.white.opacity(self.visualStyle.handleOutlineOpacity), lineWidth: 1)
                }
                .frame(width: TokenTrackerSideGeometry.visualHandleWidth)
                .offset(x: self.edge == .left
                    ? TokenTrackerSideGeometry.visualHandleOuterInset
                    : -TokenTrackerSideGeometry.visualHandleOuterInset)
        }
        .contentShape(Rectangle())
        .background {
            TokenTrackerNativeHoverRegion(
                onEnter: self.interaction.pointerEnteredTrigger,
                onExit: self.interaction.pointerExitedTrigger)
        }
        .overlay {
            TokenTrackerSideDragRegion(
                onStart: self.interaction.dragStarted,
                onClick: self.interaction.triggerClicked,
                onEnd: self.onDragEnded)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Token Tracker side handle")
        .accessibilityHint("Drag to move, or click to show providers")
        .accessibilityRepresentation {
            Button("Show Token Tracker providers", action: self.interaction.openProviderSurfaceFromShortcut)
        }
    }

    private func rail(in surfaceSize: CGSize) -> some View {
        let items = self.projection.visibleItems
        let slot = surfaceSize.width
        return ZStack {
            if items.isEmpty {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No visible providers")
            } else if let metrics = TokenTrackerProviderSurfaceMetrics.resolve(
                providerCount: items.count,
                preferredSlot: slot,
                availableLongAxis: surfaceSize.height)
            {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        self.interaction.providerClicked(item.id)
                    } label: {
                        TokenTrackerProviderContentGroup(
                            item: item,
                            slot: metrics.slot,
                            mode: .side,
                            anchorStore: self.anchorStore)
                            .frame(width: metrics.slot, height: metrics.slot)
                            .background(
                                self.interaction.hoveredProviderID == item.id
                                    ? Color.white.opacity(self.visualStyle.hoveredTileOpacity)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: metrics.slot * 0.17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .position(x: self.logoColumnX(slot: metrics.slot), y: metrics.contentBandCenter(for: index))
                    .accessibilityLabel(TokenTrackerAccessibility.providerLabel(item))
                    .accessibilityHint(TokenTrackerAccessibility.providerActionHint(
                        self.preferences.preferences.side.interaction.providerClickAction))
                }
            }
        }
        .frame(width: slot)
    }

    private func logoColumnX(slot: CGFloat) -> CGFloat {
        min(max(32, 0), slot)
    }

    private var edge: TokenTrackerHorizontalEdge {
        self.preferences.preferences.side.edge
    }

    private var attachmentEdge: TokenTrackerAttachmentEdge {
        self.edge == .left ? .left : .right
    }

    private var visualStyle: TokenTrackerSurfaceVisualStyle {
        TokenTrackerSurfaceVisualStyle(contrast: self.contrast)
    }
}

@MainActor
struct TokenTrackerSideDetailView: View {
    let item: TokenTrackerProviderItem
    @Bindable var interaction: TokenTrackerEdgeInteractionModel
    let anchorStore: TokenTrackerProviderAnchorStore?
    let presentationMode: TokenTrackerPresentationMode
    var arrowEdge: TokenTrackerCalloutArrowEdge = .right
    let openTokenTrackerSettings: @MainActor () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let edgeLength = self.arrowEdge == .bottom ? proxy.size.width : proxy.size.height
            let shape = TokenTrackerProviderDetailCalloutShape(
                arrowEdge: self.arrowEdge,
                arrowOffset: self.arrowOffset(edgeLength: edgeLength))
            TokenTrackerNotchDetailView(
                item: self.item,
                onRefresh: self.interaction.requestRefresh,
                onClose: self.interaction.closeDetail,
                onOpenSettings: self.openTokenTrackerSettings)
                .foregroundStyle(.white)
                .padding(self.contentInsets)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipShape(shape)
                .background {
                    shape.fill(.black.opacity(0.96))
                }
                .overlay {
                    shape.stroke(.white.opacity(self.visualStyle.outlineOpacity), lineWidth: 1)
                }
        }
    }

    private var visualStyle: TokenTrackerSurfaceVisualStyle {
        TokenTrackerSurfaceVisualStyle(contrast: self.contrast)
    }

    private func arrowOffset(edgeLength: CGFloat) -> CGFloat {
        guard let anchorStore = self.anchorStore,
              let anchor = anchorStore.anchor(mode: self.presentationMode, providerID: self.item.id),
              let panelFrame = anchorStore.detailPanelFrame(for: self.presentationMode)
        else {
            return TokenTrackerCalloutGeometry.clampArrowOffset(edgeLength / 2, edgeLength: edgeLength)
        }
        return TokenTrackerCalloutGeometry.arrowOffset(
            logoCenter: anchor.logoCenter,
            panelFrame: panelFrame,
            edge: self.arrowEdge)
    }

    private var contentInsets: EdgeInsets {
        switch self.arrowEdge {
        case .left:
            EdgeInsets(top: 0, leading: TokenTrackerCalloutGeometry.arrowLength, bottom: 0, trailing: 0)
        case .right:
            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: TokenTrackerCalloutGeometry.arrowLength)
        case .bottom:
            EdgeInsets(top: 0, leading: 0, bottom: TokenTrackerCalloutGeometry.arrowLength, trailing: 0)
        }
    }
}

@MainActor
struct TokenTrackerSideDetailContainerView: View {
    @Bindable var projection: TokenTrackerProviderProjection
    @Bindable var interaction: TokenTrackerEdgeInteractionModel
    let openTokenTrackerSettings: @MainActor () -> Void

    var body: some View {
        if let item = self.detailItem {
            TokenTrackerSideDetailView(
                item: item,
                interaction: self.interaction,
                anchorStore: nil,
                presentationMode: .side,
                arrowEdge: .right,
                openTokenTrackerSettings: self.openTokenTrackerSettings)
        } else {
            Color.clear
        }
    }

    private var detailItem: TokenTrackerProviderItem? {
        guard case let .detail(providerID, _) = self.interaction.state else { return nil }
        return self.projection.visibleItems.first { $0.id == providerID }
    }
}

@MainActor
struct TokenTrackerEdgeDetailContainerView: View {
    @Bindable var projection: TokenTrackerProviderProjection
    @Bindable var preferences: TokenTrackerPreferencesStore
    @Bindable var sideInteraction: TokenTrackerEdgeInteractionModel
    let anchorStore: TokenTrackerProviderAnchorStore
    let openTokenTrackerSettings: @MainActor () -> Void

    var body: some View {
        self.detailContent(
            interaction: self.sideInteraction,
            arrowEdge: self.preferences.preferences.side.edge == .left ? .left : .right)
    }

    @ViewBuilder
    private func detailContent(
        interaction: TokenTrackerEdgeInteractionModel,
        arrowEdge: TokenTrackerCalloutArrowEdge) -> some View
    {
        if let item = self.detailItem(interaction: interaction) {
            TokenTrackerSideDetailView(
                item: item,
                interaction: interaction,
                anchorStore: self.anchorStore,
                presentationMode: .side,
                arrowEdge: arrowEdge,
                openTokenTrackerSettings: self.openTokenTrackerSettings)
        } else {
            Color.clear
        }
    }

    private func detailItem(interaction: TokenTrackerEdgeInteractionModel) -> TokenTrackerProviderItem? {
        guard case let .detail(providerID, _) = interaction.state else { return nil }
        return self.projection.visibleItems.first { $0.id == providerID }
    }
}

private struct TokenTrackerSideDragRegion: NSViewRepresentable {
    let onStart: @MainActor () -> Void
    let onClick: @MainActor () -> Void
    let onEnd: @MainActor (CGRect) -> Void

    func makeNSView(context: Context) -> TokenTrackerSideDragView {
        TokenTrackerSideDragView(onStart: self.onStart, onClick: self.onClick, onEnd: self.onEnd)
    }

    func updateNSView(_ nsView: TokenTrackerSideDragView, context: Context) {
        nsView.onStart = self.onStart
        nsView.onClick = self.onClick
        nsView.onEnd = self.onEnd
    }
}

private final class TokenTrackerSideDragView: NSView {
    var onStart: @MainActor () -> Void
    var onClick: @MainActor () -> Void
    var onEnd: @MainActor (CGRect) -> Void
    private var mouseDownLocation = CGPoint.zero
    private var windowOrigin = CGPoint.zero
    private var didMove = false

    init(
        onStart: @escaping @MainActor () -> Void,
        onClick: @escaping @MainActor () -> Void,
        onEnd: @escaping @MainActor (CGRect) -> Void)
    {
        self.onStart = onStart
        self.onClick = onClick
        self.onEnd = onEnd
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        self.addCursorRect(self.bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        self.mouseDownLocation = NSEvent.mouseLocation
        self.windowOrigin = window.frame.origin
        self.didMove = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - self.mouseDownLocation.x, y: current.y - self.mouseDownLocation.y)
        if !self.didMove, hypot(delta.x, delta.y) >= 3 {
            self.didMove = true
            self.onStart()
        }
        guard self.didMove else { return }
        window.setFrameOrigin(CGPoint(x: self.windowOrigin.x + delta.x, y: self.windowOrigin.y + delta.y))
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        if self.didMove, let frame = self.window?.frame {
            self.onEnd(frame)
        } else {
            self.onClick()
        }
    }
}
