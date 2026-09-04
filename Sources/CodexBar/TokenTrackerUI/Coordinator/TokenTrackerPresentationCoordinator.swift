import AppKit

@MainActor
final class TokenTrackerPresentationCoordinator {
    private let projection: TokenTrackerProviderProjection
    private let sideInteraction: TokenTrackerEdgeInteractionModel
    private let sidePanelController: TokenTrackerSidePanelController
    private let providerDetailPanelController: TokenTrackerProviderDetailPanelController
    private let preferences: TokenTrackerPreferencesStore
    private let anchorStore: TokenTrackerProviderAnchorStore

    init(store: UsageStore, settings: SettingsStore, actions: TokenTrackerAppActions) {
        let projection = TokenTrackerProviderProjection(store: store, settings: settings)
        let preferences = settings.tokenTrackerPreferences
        let anchorStore = TokenTrackerProviderAnchorStore()
        self.preferences = preferences
        self.anchorStore = anchorStore
        let sideInteraction = TokenTrackerEdgeInteractionModel(
            placement: .side,
            preferences: preferences,
            openProviderSettings: actions.openProviderSettings,
            refreshUsage: actions.refresh,
            resolvePersistentProvider: {
                let side = preferences.preferences.side.interaction
                return projection.resolveProvider(
                    savedID: side.persistentProviderID,
                    lastOpenedID: side.lastOpenedProviderID)
            })
        self.projection = projection
        self.sideInteraction = sideInteraction
        let sidePanelController = TokenTrackerSidePanelController(
            projection: projection,
            preferences: preferences,
            interaction: sideInteraction,
            anchorStore: anchorStore,
            openTokenTrackerSettings: actions.openTokenTrackerSettings)
        self.sidePanelController = sidePanelController
        self.providerDetailPanelController = TokenTrackerProviderDetailPanelController(
            projection: projection,
            preferences: preferences,
            sideInteraction: sideInteraction,
            anchorStore: anchorStore,
            openTokenTrackerSettings: actions.openTokenTrackerSettings,
            providerSurfaceWindowNumber: { [weak sidePanelController] in sidePanelController?.windowNumber })
    }

    func start() {
        self.projection.reconcileCatalog()
        self.sideInteraction.resetForCurrentPreferences()
        self.sidePanelController.show()
        self.providerDetailPanelController.show()
    }

    func openCurrentSurfaceFromShortcut() -> Bool {
        switch self.preferences.preferences.presentationMode {
        case .side:
            self.sideInteraction.openProviderSurfaceFromShortcut()
        case .notch, .bottom, .menuBarOnly:
            return false
        }
        return true
    }
}
