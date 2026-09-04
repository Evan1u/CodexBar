import AppKit
import CodexBarCore
import Observation
import SwiftUI

struct TokenTrackerProviderAnchor: Equatable {
    let tileFrame: CGRect
    let logoCenter: CGPoint
    let surfaceVisibleFrame: CGRect
}

private struct TokenTrackerProviderAnchorKey: Hashable {
    let presentationMode: String
    let providerID: ProviderInstanceID
}

@MainActor
@Observable
final class TokenTrackerProviderAnchorStore {
    private var anchors: [TokenTrackerProviderAnchorKey: TokenTrackerProviderAnchor] = [:]
    private var detailPanelFrames: [String: CGRect] = [:]

    func update(
        mode: TokenTrackerPresentationMode,
        providerID: ProviderInstanceID,
        tileFrame: CGRect,
        logoCenter: CGPoint,
        surfaceVisibleFrame: CGRect)
    {
        guard Self.isFinite(tileFrame), logoCenter.x.isFinite, logoCenter.y.isFinite,
              Self.isFinite(surfaceVisibleFrame)
        else { return }
        let key = Self.key(mode: mode, providerID: providerID)
        let anchor = TokenTrackerProviderAnchor(
            tileFrame: tileFrame,
            logoCenter: logoCenter,
            surfaceVisibleFrame: surfaceVisibleFrame)
        guard self.anchors[key] != anchor else { return }
        self.anchors[key] = anchor
    }

    func anchor(
        mode: TokenTrackerPresentationMode,
        providerID: ProviderInstanceID) -> TokenTrackerProviderAnchor?
    {
        self.anchors[Self.key(mode: mode, providerID: providerID)]
    }

    func isAnchorOutsideSurface(
        mode: TokenTrackerPresentationMode,
        providerID: ProviderInstanceID) -> Bool
    {
        guard let anchor = self.anchor(mode: mode, providerID: providerID) else { return false }
        return !anchor.surfaceVisibleFrame.intersects(anchor.tileFrame)
    }

    func remove(mode: TokenTrackerPresentationMode, providerID: ProviderInstanceID) {
        self.anchors.removeValue(forKey: Self.key(mode: mode, providerID: providerID))
    }

    func removeAll(for mode: TokenTrackerPresentationMode) {
        self.anchors = self.anchors.filter { $0.key.presentationMode != mode.rawValue }
    }

    func updateDetailPanelFrame(_ frame: CGRect, for mode: TokenTrackerPresentationMode) {
        guard Self.isFinite(frame) else { return }
        self.detailPanelFrames[mode.rawValue] = frame
    }

    func detailPanelFrame(for mode: TokenTrackerPresentationMode) -> CGRect? {
        self.detailPanelFrames[mode.rawValue]
    }

    func removeDetailPanelFrame(for mode: TokenTrackerPresentationMode) {
        self.detailPanelFrames.removeValue(forKey: mode.rawValue)
    }

    private static func key(
        mode: TokenTrackerPresentationMode,
        providerID: ProviderInstanceID) -> TokenTrackerProviderAnchorKey
    {
        TokenTrackerProviderAnchorKey(presentationMode: mode.rawValue, providerID: providerID)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }
}

struct TokenTrackerProviderAnchorReporter: NSViewRepresentable {
    let mode: TokenTrackerPresentationMode
    let providerID: ProviderInstanceID
    let logoCenter: CGPoint?
    let onUpdate: @MainActor (TokenTrackerProviderAnchor) -> Void

    func makeNSView(context: Context) -> TokenTrackerAnchorReportingView {
        TokenTrackerAnchorReportingView(
            mode: self.mode,
            providerID: self.providerID,
            logoCenter: self.logoCenter,
            onUpdate: self.onUpdate)
    }

    func updateNSView(_ nsView: TokenTrackerAnchorReportingView, context: Context) {
        nsView.mode = self.mode
        nsView.providerID = self.providerID
        nsView.logoCenter = self.logoCenter
        nsView.onUpdate = self.onUpdate
        nsView.reportIfPossible()
    }
}

@MainActor
final class TokenTrackerAnchorReportingView: NSView {
    var mode: TokenTrackerPresentationMode
    var providerID: ProviderInstanceID
    var logoCenter: CGPoint?
    var onUpdate: @MainActor (TokenTrackerProviderAnchor) -> Void
    private var pendingAnchor: TokenTrackerProviderAnchor?
    private var reportScheduled = false

    init(
        mode: TokenTrackerPresentationMode,
        providerID: ProviderInstanceID,
        logoCenter: CGPoint?,
        onUpdate: @escaping @MainActor (TokenTrackerProviderAnchor) -> Void)
    {
        self.mode = mode
        self.providerID = providerID
        self.logoCenter = logoCenter
        self.onUpdate = onUpdate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.reportIfPossible()
    }

    func reportIfPossible() {
        guard let window, window.screen != nil else { return }
        let tileFrameInWindow = self.convert(self.bounds, to: nil)
        let tileFrame = window.convertToScreen(tileFrameInWindow)
        let logoCenter: CGPoint
        if let requestedLogoCenter = self.logoCenter {
            let logoInWindow = self.convert(requestedLogoCenter, to: nil)
            logoCenter = window.convertToScreen(CGRect(origin: logoInWindow, size: .zero)).origin
        } else {
            logoCenter = CGPoint(x: tileFrame.midX, y: tileFrame.midY)
        }
        self.pendingAnchor = TokenTrackerProviderAnchor(
            tileFrame: tileFrame,
            logoCenter: logoCenter,
            surfaceVisibleFrame: window.frame)
        guard !self.reportScheduled else { return }
        self.reportScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.reportScheduled = false
            guard let anchor = self.pendingAnchor else { return }
            self.pendingAnchor = nil
            self.onUpdate(anchor)
        }
    }
}
