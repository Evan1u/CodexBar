import AppKit
import Observation
import SwiftUI

@MainActor
final class TokenTrackerSidePanelController {
    private let projection: TokenTrackerProviderProjection
    private let preferences: TokenTrackerPreferencesStore
    private let interaction: TokenTrackerEdgeInteractionModel
    private let anchorStore: TokenTrackerProviderAnchorStore
    private let panel: NSPanel
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?
    private nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var pointerLocationTimer: Timer?
    private var observationGeneration: UInt64 = 0
    private var lastPresentationMode: TokenTrackerPresentationMode
    private var lastRestingSurface: TokenTrackerEdgeRestingSurface
    private var lastPersistentProviderID: String?
    private var lastVisibleProviderIDs: [String]

    init(
        projection: TokenTrackerProviderProjection,
        preferences: TokenTrackerPreferencesStore,
        interaction: TokenTrackerEdgeInteractionModel,
        anchorStore: TokenTrackerProviderAnchorStore,
        openTokenTrackerSettings: @escaping @MainActor () -> Void)
    {
        self.projection = projection
        self.preferences = preferences
        self.interaction = interaction
        self.anchorStore = anchorStore
        self.lastPresentationMode = preferences.preferences.presentationMode
        self.lastRestingSurface = preferences.preferences.side.interaction.restingSurface
        self.lastPersistentProviderID = preferences.preferences.side.interaction.persistentProviderID
        self.lastVisibleProviderIDs = preferences.preferences.visibleProviderIDs
        self.panel = TokenTrackerPanelFactory.makeSidePanel(contentRect: .zero)
        let contentView = NSHostingView(rootView: TokenTrackerSideView(
            projection: projection,
            interaction: interaction,
            anchorStore: anchorStore,
            preferences: preferences,
            openTokenTrackerSettings: openTokenTrackerSettings,
            onDragEnded: { [weak self] frame in self?.finishDrag(frame: frame) }))
        self.panel.contentView = contentView
        self.pointerLocationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.synchronizePointerLocation() }
        }

        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePresentation(animated: false) }
        }
        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePresentation(animated: false) }
        }
        self.observePresentationInputs()
    }

    deinit {
        self.pointerLocationTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var windowNumber: Int {
        self.panel.windowNumber
    }

    func show() {
        self.updatePresentation(animated: false)
    }

    private func observePresentationInputs() {
        self.observationGeneration &+= 1
        let generation = self.observationGeneration
        withObservationTracking {
            _ = self.preferences.preferences
            _ = self.interaction.state
            _ = self.projection.visibleItems.map(\.id)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.updatePresentation(animated: true)
                self.observePresentationInputs()
            }
        }
    }

    private func updatePresentation(animated: Bool) {
        let current = self.preferences.preferences
        let modeChanged = current.presentationMode != self.lastPresentationMode
        let placementDefaultsChanged = current.side.interaction.restingSurface != self.lastRestingSurface
            || current.side.interaction.persistentProviderID != self.lastPersistentProviderID
            || current.visibleProviderIDs != self.lastVisibleProviderIDs
        self.lastPresentationMode = current.presentationMode
        if placementDefaultsChanged {
            self.lastRestingSurface = current.side.interaction.restingSurface
            self.lastPersistentProviderID = current.side.interaction.persistentProviderID
            self.lastVisibleProviderIDs = current.visibleProviderIDs
            self.interaction.resetForCurrentPreferences()
        } else if modeChanged {
            self.interaction.presentationModeDidChange()
        }
        guard current.presentationMode == .side else {
            self.panel.orderOut(nil)
            return
        }
        if self.interaction.isDragging {
            self.panel.orderFrontRegardless()
            return
        }
        guard let screen = self.targetScreen else {
            self.panel.orderOut(nil)
            return
        }
        let snapshot = TokenTrackerScreenSnapshot(screen: screen)
        let frame = TokenTrackerSideGeometry.frame(
            size: self.panelSize(on: snapshot),
            on: snapshot,
            edge: current.side.edge,
            normalizedY: current.side.normalizedY)
        self.setFrame(frame, animated: animated)
        self.panel.orderFrontRegardless()
        self.synchronizePointerLocation()
    }

    private func panelSize(on screen: TokenTrackerScreenSnapshot) -> CGSize {
        guard self.interaction.isProviderSurfaceVisible else { return TokenTrackerSideGeometry.handleSize }
        guard let metrics = TokenTrackerSideGeometry.providerSurfaceMetrics(
            providerCount: self.projection.visibleItems.count,
            size: self.preferences.preferences.side.railSize,
            on: screen)
        else { return TokenTrackerSideGeometry.handleSize }
        return CGSize(width: metrics.slot, height: metrics.longAxis)
    }

    private var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        let snapshots = screens.map(TokenTrackerScreenSnapshot.init(screen:))
        let mainDisplayID = NSScreen.main.flatMap(Self.displayID(for:))
        guard let target = TokenTrackerSideScreenResolver.resolve(
            screens: snapshots,
            savedPersistentID: self.preferences.preferences.side.screenID,
            mouseLocation: NSEvent.mouseLocation,
            mainDisplayID: mainDisplayID)
        else { return nil }
        return zip(screens, snapshots).first(where: { $0.1 == target })?.0
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    private func finishDrag(frame: CGRect) {
        let screens = NSScreen.screens
        let snapshots = screens.map(TokenTrackerScreenSnapshot.init(screen:))
        guard let target = TokenTrackerSideGeometry.snapTarget(for: frame, screens: snapshots) else {
            self.interaction.dragEnded()
            self.updatePresentation(animated: true)
            return
        }
        self.preferences.setSideLocation(
            screenID: target.screen.persistentID,
            edge: target.edge,
            normalizedY: target.normalizedY)
        self.interaction.dragEnded()
        self.updatePresentation(animated: true)
    }

    private func setFrame(_ frame: CGRect, animated _: Bool) {
        // Keep panel and content geometry in one synchronous transaction. The former
        // layer translation could leave SwiftUI content clipped at an intermediate
        // position after rapid hover transitions.
        self.panel.setFrame(frame, display: true)
    }

    private func synchronizePointerLocation() {
        guard self.preferences.preferences.presentationMode == .side, self.panel.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        guard self.interaction.isProviderSurfaceVisible,
              let screen = self.targetScreen,
              let metrics = TokenTrackerSideGeometry.providerSurfaceMetrics(
                  providerCount: self.projection.visibleItems.count,
                  size: self.preferences.preferences.side.railSize,
                  on: TokenTrackerScreenSnapshot(screen: screen))
        else {
            self.interaction.synchronizePointerLocation(isInsidePanel: self.panel.frame.contains(pointer))
            self.interaction.providerHovered(nil)
            return
        }
        let snapshot = TokenTrackerScreenSnapshot(screen: screen)
        let handleFrame = TokenTrackerSideGeometry.frame(
            size: TokenTrackerSideGeometry.handleSize,
            on: snapshot,
            edge: self.preferences.preferences.side.edge,
            normalizedY: self.preferences.preferences.side.normalizedY)
        self.interaction.synchronizePointerLocation(
            isInsidePanel: TokenTrackerSideGeometry.containsExpandedInteractiveTarget(
                at: pointer,
                in: self.panel.frame,
                metrics: metrics,
                handleFrame: handleFrame))
        self.synchronizeHoveredProvider(at: pointer, metrics: metrics)
    }

    private func synchronizeHoveredProvider(at pointer: CGPoint, metrics: TokenTrackerProviderSurfaceMetrics) {
        guard self.interaction.isProviderSurfaceVisible,
              let index = TokenTrackerSideGeometry.providerIndex(
                  at: pointer,
                  in: self.panel.frame,
                  metrics: metrics),
              self.projection.visibleItems.indices.contains(index)
        else {
            self.interaction.providerHovered(nil)
            return
        }
        self.interaction.providerHovered(self.projection.visibleItems[index].id)
    }
}
