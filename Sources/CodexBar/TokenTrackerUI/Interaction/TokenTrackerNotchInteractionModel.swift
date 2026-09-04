import CodexBarCore
import Foundation
import Observation

enum TokenTrackerNotchInteractionState: Equatable {
    case defaultProvider
    case providersOpenPending
    case providers(transient: Bool)
    case providersClosePending
    case detail(providerID: ProviderInstanceID, pinned: Bool)
}

@MainActor
@Observable
final class TokenTrackerNotchInteractionModel {
    typealias ProviderAction = @MainActor @Sendable (ProviderInstanceID) -> Void

    private let preferences: TokenTrackerPreferencesStore
    @ObservationIgnored private let openProviderSettings: ProviderAction
    @ObservationIgnored private let refreshUsage: @MainActor @Sendable () -> Void
    @ObservationIgnored private let resolveDefaultProvider: @MainActor @Sendable () -> ProviderInstanceID?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var sessionCollapsedFromDetail = false

    var state: TokenTrackerNotchInteractionState
    var isPointerInsideTrigger = false
    var isPointerInsideProviderSurface = false
    var hoveredProviderID: ProviderInstanceID?
    var activeDetailProviderID: ProviderInstanceID?
    var isDragging = false

    init(
        preferences: TokenTrackerPreferencesStore,
        openProviderSettings: @escaping ProviderAction = { _ in },
        refreshUsage: @escaping @MainActor @Sendable () -> Void = {},
        resolveDefaultProvider: @escaping @MainActor @Sendable () -> ProviderInstanceID? = { nil })
    {
        self.preferences = preferences
        self.openProviderSettings = openProviderSettings
        self.refreshUsage = refreshUsage
        self.resolveDefaultProvider = resolveDefaultProvider
        self.state = Self.idleState(
            for: preferences.preferences.notch,
            collapsedFromDetail: false,
            resolvedProviderID: resolveDefaultProvider())
        if case let .detail(providerID, _) = self.state {
            self.activeDetailProviderID = providerID
        }
    }

    deinit {
        self.openTask?.cancel()
        self.closeTask?.cancel()
    }

    var isOverviewVisible: Bool {
        switch self.state {
        case .providers, .providersClosePending, .detail: true
        case .defaultProvider, .providersOpenPending: false
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
            for: self.preferences.preferences.notch,
            collapsedFromDetail: false,
            resolvedProviderID: self.resolveDefaultProvider())
        self.syncActiveDetail()
    }

    func presentationModeDidChange() {
        self.cancelScheduledTransitions()
        self.clearTransientInteractionState()
        self.state = Self.idleState(
            for: self.preferences.preferences.notch,
            collapsedFromDetail: self.sessionCollapsedFromDetail,
            resolvedProviderID: self.resolveDefaultProvider())
        self.syncActiveDetail()
    }

    func pointerEnteredTrigger() {
        self.isPointerInsideTrigger = true
        self.cancelClose()
        if self.state == .providersClosePending {
            self.state = .providers(transient: true)
        }
        guard self.preferences.preferences.notch.openAction == .hover,
              self.state == .defaultProvider
        else { return }
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

    func triggerClicked() {
        switch self.preferences.preferences.notch.openAction {
        case .hover, .click:
            self.openProviders(transient: self.preferences.preferences.notch.restingSurface == .defaultProvider)
        case .none:
            break
        }
    }

    func openProviderSurfaceFromShortcut() {
        self.openProviders(transient: self.preferences.preferences.notch.restingSurface == .defaultProvider)
    }

    func providerHovered(_ providerID: ProviderInstanceID?) {
        self.hoveredProviderID = providerID
    }

    func providerClicked(_ providerID: ProviderInstanceID) {
        switch self.preferences.preferences.notch.providerClickAction {
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
        if self.preferences.preferences.notch.restingSurface == .detail {
            self.sessionCollapsedFromDetail = true
        }
        self.state = Self.idleState(
            for: self.preferences.preferences.notch,
            collapsedFromDetail: self.sessionCollapsedFromDetail,
            resolvedProviderID: self.resolveDefaultProvider())
        self.syncActiveDetail()
    }

    func outsideClicked() {
        guard case let .detail(_, pinned) = self.state, !pinned else { return }
        self.closeDetail()
    }

    func escapePressed() {
        guard self.isDetailVisible else { return }
        self.closeDetail()
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

    private func showDetail(providerID: ProviderInstanceID, pinned: Bool) {
        self.cancelScheduledTransitions()
        self.preferences.update { $0.notch.lastOpenedProviderID = providerID.rawValue }
        self.state = .detail(providerID: providerID, pinned: pinned)
        self.activeDetailProviderID = providerID
    }

    private func openProviders(transient: Bool) {
        self.cancelScheduledTransitions()
        self.state = .providers(transient: transient)
        self.activeDetailProviderID = nil
    }

    private func scheduleOpen() {
        self.cancelOpen()
        self.generation &+= 1
        let token = self.generation
        self.state = .providersOpenPending
        let delay = self.preferences.preferences.notch.openDelay
        self.openTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.generation == token, self.isPointerInsideTrigger else { return }
            self.openProviders(transient: true)
        }
    }

    private func scheduleCloseIfOutside() {
        guard !self.isPointerInsideTrigger, !self.isPointerInsideProviderSurface,
              case let .providers(transient) = self.state, transient
        else { return }
        self.cancelClose()
        self.generation &+= 1
        let token = self.generation
        self.state = .providersClosePending
        let delay = self.preferences.preferences.notch.closeDelay
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
            for: self.preferences.preferences.notch,
            collapsedFromDetail: self.sessionCollapsedFromDetail,
            resolvedProviderID: self.resolveDefaultProvider())
        self.syncActiveDetail()
    }

    private static func idleState(
        for preferences: TokenTrackerNotchPreferences,
        collapsedFromDetail: Bool,
        resolvedProviderID: ProviderInstanceID?) -> TokenTrackerNotchInteractionState
    {
        switch preferences.restingSurface {
        case .defaultProvider:
            .defaultProvider
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
