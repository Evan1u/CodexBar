import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite("Token Tracker edge interaction")
struct TokenTrackerEdgeInteractionTests {
    @Test
    func `hover opens rail and transfers Handle hover to prevent flicker`() {
        let (_, model) = self.makeModel()
        model.pointerEnteredTrigger()
        #expect(model.state == .providersOpenPending)
        #expect(!model.isProviderSurfaceVisible)
        model.completePendingOpenForTesting()
        #expect(model.state == .providers(transient: true))
        #expect(model.isPointerInsideProviderSurface)
        #expect(!model.isPointerInsideTrigger)

        model.pointerExitedProviderSurface()
        #expect(model.state == .providersClosePending)
        model.pointerEnteredProviderSurface()
        #expect(model.state == .providers(transient: true))
    }

    @Test
    func `leaving handle cancels pending hover open`() {
        let (_, model) = self.makeModel()
        model.pointerEnteredTrigger()
        model.pointerExitedTrigger()
        #expect(model.state == .handle)
        model.completePendingOpenForTesting()
        #expect(model.state == .handle)
    }

    @Test
    func `panel coordinate synchronization corrects stale hover tracking`() {
        let (_, model) = self.makeModel()
        model.synchronizePointerLocation(isInsidePanel: true)
        #expect(model.state == .providersOpenPending)

        model.completePendingOpenForTesting()
        #expect(model.state == .providers(transient: true))
        model.pointerExitedTrigger()
        model.pointerExitedProviderSurface()
        #expect(model.state == .providersClosePending)

        model.synchronizePointerLocation(isInsidePanel: true)
        #expect(model.state == .providers(transient: true))

        model.synchronizePointerLocation(isInsidePanel: false)
        #expect(model.state == .providersClosePending)
    }

    @Test
    func `provider hover state follows the current provider and clears outside a tile`() {
        let (_, model) = self.makeModel()

        model.providerHovered(.codex)
        #expect(model.hoveredProviderID == .codex)
        model.providerHovered(.claude)
        #expect(model.hoveredProviderID == .claude)
        model.providerHovered(nil)
        #expect(model.hoveredProviderID == nil)
    }

    @Test
    func `shortcut opens rail even when pointer action is disabled`() {
        let (preferences, model) = self.makeModel()
        preferences.update { $0.side.interaction.openAction = .none }

        model.openProviderSurfaceFromShortcut()

        #expect(model.state == .providers(transient: true))
    }

    @Test
    func `provider click branches keep settings separate from detail state`() {
        var openedSettings: ProviderInstanceID?
        let (preferences, model) = self.makeModel { openedSettings = $0 }

        model.providerClicked(.codex)
        #expect(model.state == .detail(providerID: .codex, pinned: false))
        #expect(preferences.preferences.side.interaction.lastOpenedProviderID == "codex")

        preferences.update { $0.side.interaction.providerClickAction = .togglePinnedDetail }
        model.providerClicked(.claude)
        #expect(model.state == .detail(providerID: .claude, pinned: true))
        model.outsideClicked()
        #expect(model.state == .detail(providerID: .claude, pinned: true))
        model.providerClicked(.deepseek)
        #expect(model.state == .detail(providerID: .deepseek, pinned: true))
        model.providerClicked(.deepseek)
        #expect(model.state == .handle)

        preferences.update { $0.side.interaction.providerClickAction = .openProviderSettings }
        let stateBeforeSettings = model.state
        model.providerClicked(.claude)
        #expect(openedSettings == .claude)
        #expect(model.state == stateBeforeSettings)
    }

    @Test
    func `resting providers stays open and persistent detail collapses only for session`() {
        let (preferences, model) = self.makeModel()
        preferences.update { $0.side.interaction.restingSurface = .providers }
        model.resetForCurrentPreferences()
        #expect(model.state == .providers(transient: false))
        model.pointerExitedProviderSurface()
        #expect(model.state == .providers(transient: false))

        preferences.update { $0.side.interaction.restingSurface = .detail }
        model.resetForCurrentPreferences()
        #expect(model.state == .detail(providerID: .codex, pinned: false))
        model.escapePressed()
        #expect(model.state == .providers(transient: false))
        #expect(preferences.preferences.side.interaction.restingSurface == .detail)
    }

    @Test
    func `dragging remembers visible rail then returns to effective idle surface`() {
        let (_, model) = self.makeModel()
        model.pointerEnteredTrigger()
        model.completePendingOpenForTesting()
        model.dragStarted()
        #expect(model.state == .dragging)
        #expect(model.isDragging)
        #expect(model.isProviderSurfaceVisible)

        model.dragEnded()
        #expect(model.state == .handle)
        #expect(!model.isDragging)
    }

    @Test
    func `dragging rail while detail is open clears session pin`() {
        let (preferences, model) = self.makeModel()
        preferences.update { $0.side.interaction.providerClickAction = .togglePinnedDetail }
        model.providerClicked(.codex)
        #expect(model.state == .detail(providerID: .codex, pinned: true))

        model.dragStarted()
        #expect(model.state == .dragging)
        #expect(model.isProviderSurfaceVisible)
        model.dragEnded()
        #expect(model.state == .handle)
    }

    @Test
    func `presentation mode change preserves Side session collapse`() {
        self.expectPresentationModeChangePreservesSessionCollapse()
    }

    private func expectPresentationModeChangePreservesSessionCollapse() {
        let name = "TokenTrackerEdgeInteractionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = TokenTrackerPreferencesStore(
            userDefaults: defaults,
            availableProviderIDs: [.codex, .claude, .deepseek])
        preferences.update { $0.side.interaction.restingSurface = .detail }
        let model = self.makeModel(preferences: preferences, placement: .side)
        model.escapePressed()
        #expect(model.state == .providers(transient: false))

        model.presentationModeDidChange()

        #expect(model.state == .providers(transient: false))
        #expect(preferences.preferences.side.interaction.restingSurface == .detail)
    }

    @Test
    func `presentation mode change cancels pending drag and pin state`() {
        let (preferences, model) = self.makeModel()
        model.pointerEnteredTrigger()
        #expect(model.state == .providersOpenPending)
        model.presentationModeDidChange()
        #expect(model.state == .handle)
        #expect(!model.isPointerInsideTrigger)
        model.completePendingOpenForTesting()
        #expect(model.state == .handle)

        preferences.update { $0.side.interaction.providerClickAction = .togglePinnedDetail }
        model.providerClicked(.codex)
        #expect(model.state == .detail(providerID: .codex, pinned: true))
        model.presentationModeDidChange()
        #expect(model.state == .handle)
        #expect(model.activeDetailProviderID == nil)

        model.dragStarted()
        #expect(model.state == .dragging)
        model.presentationModeDidChange()
        #expect(model.state == .handle)
        #expect(!model.isDragging)
        #expect(!model.isProviderSurfaceVisible)
    }

    @Test
    func `placement default change clears an existing edge session collapse`() {
        let (preferences, model) = self.makeModel()
        preferences.update { $0.side.interaction.restingSurface = .detail }
        model.resetForCurrentPreferences()
        model.escapePressed()
        #expect(model.state == .providers(transient: false))

        preferences.update { $0.side.interaction.restingSurface = .handle }
        model.resetForCurrentPreferences()
        preferences.update { $0.side.interaction.restingSurface = .detail }
        model.resetForCurrentPreferences()

        #expect(model.state == .detail(providerID: .codex, pinned: false))
    }

    private func makeModel(
        openSettings: @escaping @MainActor @Sendable (ProviderInstanceID) -> Void = { _ in })
        -> (TokenTrackerPreferencesStore, TokenTrackerEdgeInteractionModel)
    {
        let name = "TokenTrackerEdgeInteractionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = TokenTrackerPreferencesStore(
            userDefaults: defaults,
            availableProviderIDs: [.codex, .claude, .deepseek])
        let model = self.makeModel(
            preferences: preferences,
            placement: .side,
            openSettings: openSettings)
        return (preferences, model)
    }

    private func makeModel(
        preferences: TokenTrackerPreferencesStore,
        placement: TokenTrackerEdgePlacement,
        openSettings: @escaping @MainActor @Sendable (ProviderInstanceID) -> Void = { _ in })
        -> TokenTrackerEdgeInteractionModel
    {
        TokenTrackerEdgeInteractionModel(
            placement: placement,
            preferences: preferences,
            openProviderSettings: openSettings,
            resolvePersistentProvider: { .codex })
    }
}
