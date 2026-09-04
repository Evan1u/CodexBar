import CodexBarCore

@MainActor
struct TokenTrackerAppActions {
    let refresh: @MainActor @Sendable () -> Void
    let openTokenTrackerSettings: @MainActor @Sendable () -> Void
    let openProviderSettings: @MainActor @Sendable (ProviderInstanceID) -> Void
    let quit: @MainActor @Sendable () -> Void

    static let inert = Self(
        refresh: {},
        openTokenTrackerSettings: {},
        openProviderSettings: { _ in },
        quit: {})

    static func settingsPane(for providerID: ProviderInstanceID) -> SettingsPane {
        providerID.firstPartyProvider == nil ? .plugins : .provider(providerID)
    }
}
