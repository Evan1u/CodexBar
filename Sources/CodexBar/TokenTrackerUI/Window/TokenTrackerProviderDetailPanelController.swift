import AppKit
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class TokenTrackerProviderDetailPanelController {
    private let projection: TokenTrackerProviderProjection
    private let preferences: TokenTrackerPreferencesStore
    private let sideInteraction: TokenTrackerEdgeInteractionModel
    private let anchorStore: TokenTrackerProviderAnchorStore
    private let providerSurfaceWindowNumber: @MainActor () -> Int?
    private let panel: NSPanel
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?
    private nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var localEventMonitor: Any?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private var pendingEventMonitorActivation: Task<Void, Never>?
    private var observationGeneration: UInt64 = 0
    private var measuredDetail: DetailMeasurement?
    private var pendingMeasurement: DetailMeasurementKey?

    private struct DetailMeasurement: Equatable {
        let key: DetailMeasurementKey
        let bodyHeight: CGFloat
    }

    private struct DetailMeasurementKey: Equatable {
        let mode: TokenTrackerPresentationMode
        let item: TokenTrackerProviderItem
    }

    init(
        projection: TokenTrackerProviderProjection,
        preferences: TokenTrackerPreferencesStore,
        sideInteraction: TokenTrackerEdgeInteractionModel,
        anchorStore: TokenTrackerProviderAnchorStore,
        openTokenTrackerSettings: @escaping @MainActor () -> Void,
        providerSurfaceWindowNumber: @escaping @MainActor () -> Int?)
    {
        self.projection = projection
        self.preferences = preferences
        self.sideInteraction = sideInteraction
        self.anchorStore = anchorStore
        self.providerSurfaceWindowNumber = providerSurfaceWindowNumber
        self.panel = TokenTrackerPanelFactory.makeProviderDetailPanel(contentRect: .zero)
        self.panel.contentView = NSHostingView(rootView: TokenTrackerEdgeDetailContainerView(
            projection: projection,
            preferences: preferences,
            sideInteraction: sideInteraction,
            anchorStore: anchorStore,
            openTokenTrackerSettings: openTokenTrackerSettings))

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
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        self.pendingEventMonitorActivation?.cancel()
    }

    func show() {
        self.updatePresentation(animated: false)
    }

    private func observePresentationInputs() {
        self.observationGeneration &+= 1
        let generation = self.observationGeneration
        withObservationTracking {
            _ = self.preferences.preferences
            _ = self.sideInteraction.state
            _ = self.projection.visibleItems
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
        guard let interaction = self.currentInteraction,
              interaction.isDetailVisible,
              let item = self.detailItem(interaction: interaction),
              let detailFrame = self.detailFrame(for: current.presentationMode, item: item)
        else {
            self.anchorStore.removeDetailPanelFrame(for: current.presentationMode)
            self.updateEventMonitors(active: false)
            self.panel.orderOut(nil)
            return
        }
        self.closeIfAnchorIsOutsideSurface(item: item, mode: current.presentationMode)
        guard interaction.isDetailVisible else {
            self.updateEventMonitors(active: false)
            self.panel.orderOut(nil)
            return
        }
        self.updateEventMonitors(active: true)
        self.setFrame(detailFrame, animated: animated)
        self.panel.orderFrontRegardless()
        self.scheduleFittingMeasurement(for: item, mode: current.presentationMode)
    }

    private var currentInteraction: TokenTrackerEdgeInteractionModel? {
        switch self.preferences.preferences.presentationMode {
        case .side: self.sideInteraction
        case .notch, .bottom, .menuBarOnly: nil
        }
    }

    private func detailItem(interaction: TokenTrackerEdgeInteractionModel) -> TokenTrackerProviderItem? {
        guard case let .detail(providerID, _) = interaction.state else { return nil }
        return self.projection.visibleItems.first { $0.id == providerID }
    }

    private func closeIfAnchorIsOutsideSurface(
        item: TokenTrackerProviderItem,
        mode: TokenTrackerPresentationMode)
    {
        guard mode == .side,
              self.anchorStore.isAnchorOutsideSurface(mode: mode, providerID: item.id)
        else { return }
        self.currentInteraction?.closeDetail()
    }

    private func detailFrame(for mode: TokenTrackerPresentationMode, item: TokenTrackerProviderItem) -> CGRect? {
        let bodyHeight = self.bodyHeight(for: item, mode: mode)
        switch mode {
        case .side:
            guard let screen = self.sideTargetScreen else { return nil }
            let current = self.preferences.preferences
            let snapshot = TokenTrackerScreenSnapshot(screen: screen)
            let railSize = CGSize(
                width: TokenTrackerSideGeometry.railWidth(for: current.side.railSize),
                height: TokenTrackerSideGeometry.railHeight(
                    providerCount: self.projection.visibleItems.count,
                    on: snapshot))
            let railFrame = TokenTrackerSideGeometry.frame(
                size: railSize,
                on: snapshot,
                edge: current.side.edge,
                normalizedY: current.side.normalizedY)
            return TokenTrackerSideGeometry.detailFrame(
                size: TokenTrackerDetailSizing.sideSize(bodyHeight: bodyHeight),
                adjacentTo: railFrame,
                on: snapshot,
                edge: current.side.edge)
        case .bottom, .notch, .menuBarOnly:
            return nil
        }
    }

    private func bodyHeight(for item: TokenTrackerProviderItem, mode: TokenTrackerPresentationMode) -> CGFloat {
        let key = DetailMeasurementKey(mode: mode, item: item)
        if let measuredDetail = self.measuredDetail, measuredDetail.key == key {
            return measuredDetail.bodyHeight
        }
        return TokenTrackerDetailSizing.initialBodyHeight(visibleHeight: self.visibleHeight(for: mode))
    }

    private func visibleHeight(for mode: TokenTrackerPresentationMode) -> CGFloat {
        switch mode {
        case .side:
            self.sideTargetScreen.map { TokenTrackerScreenSnapshot(screen: $0).visibleFrame.height } ?? 0
        case .bottom, .notch, .menuBarOnly:
            0
        }
    }

    private func scheduleFittingMeasurement(for item: TokenTrackerProviderItem, mode: TokenTrackerPresentationMode) {
        let key = DetailMeasurementKey(mode: mode, item: item)
        guard self.measuredDetail?.key != key, self.pendingMeasurement != key else { return }
        self.pendingMeasurement = key
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.pendingMeasurement = nil }
            guard self.currentInteraction?.isDetailVisible == true,
                  self.preferences.preferences.presentationMode == mode
            else { return }

            let host = NSHostingView(rootView: TokenTrackerNotchDetailView(
                item: item,
                onRefresh: self.currentInteraction?.requestRefresh ?? {},
                onClose: self.currentInteraction?.closeDetail ?? {},
                onOpenSettings: {}))
            host.frame = NSRect(x: 0, y: 0, width: TokenTrackerDetailSizing.bodyWidth, height: 1)
            host.layoutSubtreeIfNeeded()
            let bodyHeight = TokenTrackerDetailSizing.bodyHeight(
                fittingHeight: ceil(host.fittingSize.height),
                visibleHeight: self.visibleHeight(for: mode))
            guard bodyHeight > 0 else { return }
            self.measuredDetail = DetailMeasurement(key: key, bodyHeight: bodyHeight)
            self.updatePresentation(animated: true)
        }
    }

    private var sideTargetScreen: NSScreen? {
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

    private func setFrame(_ frame: CGRect, animated: Bool) {
        self.anchorStore.updateDetailPanelFrame(
            frame,
            for: .side)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(frame, display: true)
            }
        } else {
            self.panel.setFrame(frame, display: true)
        }
    }

    private func updateEventMonitors(active: Bool) {
        guard active else {
            self.pendingEventMonitorActivation?.cancel()
            self.pendingEventMonitorActivation = nil
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
                self.localEventMonitor = nil
            }
            if let globalMouseMonitor {
                NSEvent.removeMonitor(globalMouseMonitor)
                self.globalMouseMonitor = nil
            }
            return
        }
        guard self.localEventMonitor == nil,
              self.globalMouseMonitor == nil,
              self.pendingEventMonitorActivation == nil
        else { return }

        self.pendingEventMonitorActivation = Task { @MainActor [weak self] in
            // A provider Button action is delivered while the originating mouse event is
            // still being dispatched. Installing an outside-click monitor after only a
            // task yield can observe that same event and immediately dismiss the detail.
            // Let the click complete before listening for the next outside interaction.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.pendingEventMonitorActivation = nil
            guard self.currentInteraction?.isDetailVisible == true else { return }
            self.installEventMonitors()
        }
    }

    private func installEventMonitors() {
        guard self.localEventMonitor == nil, self.globalMouseMonitor == nil else { return }

        let localHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let eventWindowNumber = event.windowNumber
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isEscape {
                    self.currentInteraction?.escapePressed()
                } else if eventWindowNumber != self.panel.windowNumber,
                          eventWindowNumber != self.providerSurfaceWindowNumber()
                {
                    self.currentInteraction?.outsideClicked()
                }
            }
            return event
        }
        self.localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: localHandler)

        let globalHandler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.currentInteraction?.outsideClicked() }
        }
        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: globalHandler)
    }
}
