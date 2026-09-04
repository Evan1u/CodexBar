import CodexBarCore
import Foundation
import Observation

enum TokenTrackerEdgeInteractionState: Equatable {
    case handle
    case providersOpenPending
    case providers(transient: Bool)
    case providersClosePending
    case detail(providerID: ProviderInstanceID, pinned: Bool)
    case dragging
}

enum TokenTrackerEdgePlacement {
    case side
    case bottom
}

@MainActor
@Observable
final class TokenTrackerEdgeInteractionModel {
    typealias ProviderAction = @MainActor @Sendable (ProviderInstanceID) -> Void

    private let placement: TokenTrackerEdgePlacement
    private let preferences: TokenTrackerPreferencesStore
    @ObservationIgnored private let openProviderSettings: ProviderAction
    @ObservationIgnored private let refreshUsage: @MainActor @Sendable () -> Void
    @ObservationIgnored private let resolvePersistentProvider: @MainActor @Sendable () -> ProviderInstanceID?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var sessionCollapsedFromDetail = false
    private var providerSurfaceVisibleBeforeDrag = false

    var state: TokenTrackerEdgeInteractionState
    var isPointerInsideTrigger = false
    var isPointerInsideProviderSurface = false
    var hoveredProviderID: ProviderInstanceID?
    var activeDetailProviderID: ProviderInstanceID?
    var isDragging = false

    init(
        placement: TokenTrackerEdgePlacement,
        preferences: TokenTrackerPreferencesStore,
        openProviderSettings: @escaping ProviderAction = { _ in },
        refreshUsage: @escaping @MainActor @Sendable () -> Void = {},
        resolvePersistentProvider: @escaping @MainActor @Sendable () -> ProviderInstanceID? = { nil })
    {
        self.placement = placement
        self.preferences = preferences
        self.openProviderSettings = openProviderSettings
        self.refreshUsage = refreshUsage
        self.resolvePersistentProvider = resolvePersistentProvider
        self.state = Self.idleState(
            for: Self.interactionPreferences(in: preferences.preferences, placement: placement),
            collapsedFromDetail: false,
            resolvedProviderID: resolvePersistentProvider())
        self.syncActiveDetail()
    }

    deinit {
        self.openTask?.cancel()
        self.closeTask?.cancel()
    }

    var isProviderSurfaceVisible: Bool {
        switch self.state {
        case .providers, .providersClosePending, .detail: true
        case .dragging: self.providerSurfaceVisibleBeforeDrag
        case .handle, .providersOpenPending: false
        }
    }

    var isDetailVisible: Bool {
        if case .detail = self.state { true } else { false }
    }

    func resetForCurrentPreferences() {
        self.cancelScheduledTransitions()
        self.sessionCollapsedFromDetail = false
        self.clearTransientInteractionState()
        self.state = Self.idleState(
            for: self.currentPreferences,
            collapsedFromDetail: false,
            resolvedProviderID: self.resolvePersistentProvider())
        self.syncActiveDetail()
    }

    func presentationModeDidChange() {
        self.cancelScheduledTransitions()
        self.clearTransientInteractionState()
        self.state = Self.idleState(
            for: self.currentPreferences,
            collapsedFromDetail: self.sessionCollapsedFromDetail,
            resolvedProviderID: self.resolvePersistentProvider())
        self.syncActiveDetail()
    }

    func pointerEnteredTrigger() {
        self.isPointerInsideTrigger = true
        self.cancelClose()
        if self.state == .providersClosePending {
            self.state = .providers(transient: true)
        }
        guard self.currentPreferences.openAction == .hover, self.state == .handle else { return }
        self.scheduleOpen()
    }

    func pointerExitedTrigger() {
        self.isPointerInsideTrigger = false
        if self.state == .providersOpenPending {
            self.cancelScheduledTransitions()
            self.returnToIdle()
            return
        }
        self.scheduleCloseIfOutside()
    }

    func pointerEnteredProviderSurface() {
        self.isPointerInsideProviderSurface = true
        self.cancelClose()
        if self.state == .providersClosePending {
            self.state = .providers(transient: true)
        }
    }

    func pointerExitedProviderSurface() {
        self.isPointerInsideProviderSurface = false
        self.hoveredProviderID = nil
        self.scheduleCloseIfOutside()
    }

    func synchronizePointerLocation(isInsidePanel: Bool) {
        if self.isProviderSurfaceVisible {
            if isInsidePanel, !self.isPointerInsideProviderSurface {
                self.pointerEnteredProviderSurface()
            } else if !isInsidePanel, self.isPointerInsideProviderSurface {
                self.pointerExitedProviderSurface()
            }
        } else if isInsidePanel, !self.isPointerInsideTrigger {
            self.pointerEnteredTrigger()
        } else if !isInsidePanel, self.isPointerInsideTrigger {
            self.pointerExitedTrigger()
        }
    }

    func triggerClicked() {
        switch self.currentPreferences.openAction {
        case .hover, .click:
            self.openProviders(transient: self.currentPreferences.restingSurface == .handle)
        case .none:
            break
        }
    }

    func openProviderSurfaceFromShortcut() {
        self.openProviders(transient: self.currentPreferences.restingSurface == .handle)
    }

    func providerHovered(_ providerID: ProviderInstanceID?) {
        guard self.hoveredProviderID != providerID else { return }
        self.hoveredProviderID = providerID
    }

    func providerClicked(_ providerID: ProviderInstanceID) {
        switch self.currentPreferences.providerClickAction {
        case .showDetail:
            self.showDetail(providerID: providerID, pinned: false)
        case .togglePinnedDetail:
            if self.state == .detail(providerID: providerID, pinned: true) {
                self.closeDetail()
            } else {
                self.showDetail(providerID: providerID, pinned: true)
            }
        case .openProviderSettings:
            self.openProviderSettings(providerID)
        }
    }

    func closeDetail() {
        self.cancelScheduledTransitions()
        if self.currentPreferences.restingSurface == .detail {
            self.sessionCollapsedFromDetail = true
        }
        self.returnToIdle()
    }

    func outsideClicked() {
        guard case let .detail(_, pinned) = self.state, !pinned else { return }
        self.closeDetail()
    }

    func escapePressed() {
        guard self.isDetailVisible else { return }
        self.closeDetail()
    }

    func dragStarted() {
        self.cancelScheduledTransitions()
        self.providerSurfaceVisibleBeforeDrag = self.isProviderSurfaceVisible
        self.isDragging = true
        self.state = .dragging
        self.activeDetailProviderID = nil
    }

    func dragEnded() {
        guard self.isDragging else { return }
        self.isDragging = false
        self.returnToIdle()
    }

    func requestRefresh() {
        self.refreshUsage()
    }

    func completePendingOpenForTesting() {
        guard self.state == .providersOpenPending else { return }
        self.openProviders(transient: true)
    }

    func completePendingCloseForTesting() {
        guard self.state == .providersClosePending,
              !self.isPointerInsideTrigger,
              !self.isPointerInsideProviderSurface
        else { return }
        self.returnToIdle()
    }

    private var currentPreferences: TokenTrackerEdgeInteractionPreferences {
        Self.interactionPreferences(in: self.preferences.preferences, placement: self.placement)
    }

    private static func interactionPreferences(
        in preferences: TokenTrackerPreferences,
        placement: TokenTrackerEdgePlacement) -> TokenTrackerEdgeInteractionPreferences
    {
        switch placement {
        case .side: preferences.side.interaction
        case .bottom: preferences.bottom.interaction
        }
    }

    private func showDetail(providerID: ProviderInstanceID, pinned: Bool) {
        self.cancelScheduledTransitions()
        self.preferences.update { preferences in
            switch self.placement {
            case .side: preferences.side.interaction.lastOpenedProviderID = providerID.rawValue
            case .bottom: preferences.bottom.interaction.lastOpenedProviderID = providerID.rawValue
            }
        }
        self.state = .detail(providerID: providerID, pinned: pinned)
        self.activeDetailProviderID = providerID
    }

    private func openProviders(transient: Bool) {
        self.cancelScheduledTransitions()
        // Replacing the Handle with a rail recreates its AppKit tracking view under
        // the stationary pointer. Carry that hover into the rail so the Handle's
        // teardown `mouseExited` cannot schedule an immediate close.
        self.isPointerInsideProviderSurface = self.isPointerInsideProviderSurface || self.isPointerInsideTrigger
        // The Handle's tracking view is about to be replaced. Its former state
        // must not keep the Rail open after the pointer has physically left the
        // new panel.
        self.isPointerInsideTrigger = false
        self.state = .providers(transient: transient)
        self.activeDetailProviderID = nil
    }

    private func scheduleOpen() {
        self.cancelOpen()
        self.generation &+= 1
        let token = self.generation
        self.state = .providersOpenPending
        let delay = self.currentPreferences.openDelay
        self.openTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.generation == token, self.isPointerInsideTrigger else { return }
            self.openProviders(transient: true)
        }
    }

    private func scheduleCloseIfOutside() {
        guard !self.isDragging,
              !self.isPointerInsideTrigger,
              !self.isPointerInsideProviderSurface,
              case let .providers(transient) = self.state,
              transient
        else { return }
        self.cancelClose()
        self.generation &+= 1
        let token = self.generation
        self.state = .providersClosePending
        let delay = self.currentPreferences.closeDelay
        self.closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.generation == token,
                  !self.isPointerInsideTrigger, !self.isPointerInsideProviderSurface
            else { return }
            self.returnToIdle()
        }
    }

    private func returnToIdle() {
        self.cancelScheduledTransitions()
        self.state = Self.idleState(
            for: self.currentPreferences,
            collapsedFromDetail: self.sessionCollapsedFromDetail,
            resolvedProviderID: self.resolvePersistentProvider())
        self.syncActiveDetail()
    }

    private static func idleState(
        for preferences: TokenTrackerEdgeInteractionPreferences,
        collapsedFromDetail: Bool,
        resolvedProviderID: ProviderInstanceID?) -> TokenTrackerEdgeInteractionState
    {
        switch preferences.restingSurface {
        case .handle:
            .handle
        case .providers:
            .providers(transient: false)
        case .detail:
            if collapsedFromDetail {
                .providers(transient: false)
            } else if let providerID = resolvedProviderID {
                .detail(providerID: providerID, pinned: false)
            } else {
                .providers(transient: false)
            }
        }
    }

    private func syncActiveDetail() {
        if case let .detail(providerID, _) = self.state {
            self.activeDetailProviderID = providerID
        } else {
            self.activeDetailProviderID = nil
        }
    }

    private func clearTransientInteractionState() {
        self.isPointerInsideTrigger = false
        self.isPointerInsideProviderSurface = false
        self.hoveredProviderID = nil
        self.isDragging = false
        self.providerSurfaceVisibleBeforeDrag = false
    }

    private func cancelScheduledTransitions() {
        self.generation &+= 1
        self.cancelOpen()
        self.cancelClose()
    }

    private func cancelOpen() {
        self.openTask?.cancel()
        self.openTask = nil
    }

    private func cancelClose() {
        self.closeTask?.cancel()
        self.closeTask = nil
    }
}
