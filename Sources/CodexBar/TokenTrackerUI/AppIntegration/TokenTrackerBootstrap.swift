import Foundation

@MainActor
final class TokenTrackerBootstrap {
    private let coordinator: TokenTrackerPresentationCoordinator
    private var hasStarted = false

    init(store: UsageStore, settings: SettingsStore, actions: TokenTrackerAppActions = .inert) {
        self.coordinator = TokenTrackerPresentationCoordinator(store: store, settings: settings, actions: actions)
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
        self.coordinator.start()
    }

    func openCurrentSurfaceFromShortcut() -> Bool {
        self.coordinator.openCurrentSurfaceFromShortcut()
    }
}
