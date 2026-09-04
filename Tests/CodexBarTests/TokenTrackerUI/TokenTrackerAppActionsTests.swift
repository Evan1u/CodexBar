import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite("Token Tracker app actions")
struct TokenTrackerAppActionsTests {
    @Test
    func `provider settings route first party and plugins to existing panes`() throws {
        #expect(TokenTrackerAppActions.settingsPane(for: .codex) == .provider(.codex))
        let pluginID = try #require(ProviderInstanceID(rawValue: "example-plugin"))
        #expect(TokenTrackerAppActions.settingsPane(for: pluginID) == .plugins)
    }

    @Test
    func `daily operation commands stay independently routable`() {
        var refreshCount = 0
        var tokenTrackerSettingsCount = 0
        var providerID: ProviderInstanceID?
        var quitCount = 0
        let actions = TokenTrackerAppActions(
            refresh: { refreshCount += 1 },
            openTokenTrackerSettings: { tokenTrackerSettingsCount += 1 },
            openProviderSettings: { providerID = $0 },
            quit: { quitCount += 1 })

        actions.refresh()
        actions.openTokenTrackerSettings()
        actions.openProviderSettings(.claude)
        actions.quit()

        #expect(refreshCount == 1)
        #expect(tokenTrackerSettingsCount == 1)
        #expect(providerID == .claude)
        #expect(quitCount == 1)
    }
}
