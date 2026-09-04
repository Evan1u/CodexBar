import AppKit
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class TokenTrackerNotchPanelController {
    private let projection: TokenTrackerProviderProjection
    private let preferences: TokenTrackerPreferencesStore
    private let interaction: TokenTrackerNotchInteractionModel
    private let panel: NSPanel
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?
    private nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var localEventMonitor: Any?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private var observationGeneration: UInt64 = 0
    private var lastPresentationMode: TokenTrackerPresentationMode
    private var lastRestingSurface: TokenTrackerNotchRestingSurface
    private var lastDefaultProviderID: String?
    private var lastVisibleProviderIDs: [String]

    init(
        projection: TokenTrackerProviderProjection,
        preferences: TokenTrackerPreferencesStore,
        interaction: TokenTrackerNotchInteractionModel,
        openTokenTrackerSettings: @escaping @MainActor () -> Void)
    {
        self.projection = projection
        self.preferences = preferences
        self.interaction = interaction
        self.lastPresentationMode = preferences.preferences.presentationMode
        self.lastRestingSurface = preferences.preferences.notch.restingSurface
        self.lastDefaultProviderID = preferences.preferences.notch.defaultProviderID
        self.lastVisibleProviderIDs = preferences.preferences.visibleProviderIDs
        self.panel = TokenTrackerPanelFactory.makeNotchPanel(contentRect: .zero)
        self.panel.contentView = NSHostingView(rootView: TokenTrackerNotchView(
            projection: projection,
            interaction: interaction,
            preferences: preferences,
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
        let placementDefaultsChanged = current.notch.restingSurface != self.lastRestingSurface
            || current.notch.defaultProviderID != self.lastDefaultProviderID
            || current.visibleProviderIDs != self.lastVisibleProviderIDs
        self.lastPresentationMode = current.presentationMode
        if placementDefaultsChanged {
            self.lastRestingSurface = current.notch.restingSurface
            self.lastDefaultProviderID = current.notch.defaultProviderID
            self.lastVisibleProviderIDs = current.visibleProviderIDs
            self.interaction.resetForCurrentPreferences()
        } else if modeChanged {
            self.interaction.presentationModeDidChange()
        }
        self.updateEventMonitors(
            active: current.presentationMode == .notch && self.interaction.isDetailVisible)
        guard current.presentationMode == .notch else {
            self.panel.orderOut(nil)
            return
        }
        guard let screen = self.targetScreen else {
            self.panel.orderOut(nil)
            return
        }
        let snapshot = TokenTrackerScreenSnapshot(screen: screen)
        let frame = TokenTrackerNotchGeometry.frame(size: self.panelSize(on: snapshot), on: snapshot)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(frame, display: true)
            }
        } else {
            self.panel.setFrame(frame, display: true)
        }
        self.panel.orderFrontRegardless()
    }

    private func panelSize(on screen: TokenTrackerScreenSnapshot) -> CGSize {
        let compact = TokenTrackerNotchGeometry.compactSize(on: screen)
        guard self.interaction.isOverviewVisible else { return compact }
        let preferredWidth: CGFloat = switch self.preferences.preferences.notch.overviewWidth {
        case .compact: 360
        case .standard: 480
        case .wide: 640
        }
        let width = max(compact.width, preferredWidth)
        let height: CGFloat = self.interaction.isDetailVisible ? 462 : 131
        return CGSize(width: width, height: height)
    }

    private var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        let snapshots = screens.map(TokenTrackerScreenSnapshot.init(screen:))
        let mainDisplayID = NSScreen.main.flatMap(Self.displayID(for:))
        guard let target = TokenTrackerScreenResolver.resolve(
            screens: snapshots,
            savedPersistentID: self.preferences.preferences.notch.screenID,
            mouseLocation: NSEvent.mouseLocation,
            mainDisplayID: mainDisplayID)
        else { return nil }
        return zip(screens, snapshots).first(where: { $0.1 == target })?.0
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    private func updateEventMonitors(active: Bool) {
        guard active else {
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
        guard self.localEventMonitor == nil, self.globalMouseMonitor == nil else { return }

        let localHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let eventWindowNumber = event.windowNumber
            Task { @MainActor [weak self] in
                if isEscape {
                    self?.interaction.escapePressed()
                } else if let self, eventWindowNumber != self.panel.windowNumber {
                    self.interaction.outsideClicked()
                }
            }
            return event
        }
        self.localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: localHandler)

        let globalHandler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.interaction.outsideClicked() }
        }
        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: globalHandler)
    }
}
