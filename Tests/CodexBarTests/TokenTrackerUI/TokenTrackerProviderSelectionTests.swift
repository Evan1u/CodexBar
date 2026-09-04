import CodexBarCore
import Testing
@testable import CodexBar

@Suite("Token Tracker provider selection")
struct TokenTrackerProviderSelectionTests {
    @Test
    func `fallback order is strict and saved disabled remains selected`() {
        let visible: [ProviderInstanceID] = [.codex, .claude, .deepseek]
        let catalog = visible
        let configured: Set<ProviderInstanceID> = [.claude]

        #expect(self.resolve("codex", "deepseek", visible, catalog, configured) == .codex)
        #expect(self.resolve("missing", "deepseek", visible, catalog, configured) == .deepseek)
        #expect(self.resolve("missing", "also-missing", visible, catalog, configured) == .claude)
        #expect(self.resolve(nil, nil, visible, catalog, []) == .codex)
        #expect(self.resolve("codex", nil, [.claude], catalog, []) == .claude)
        #expect(self.resolve(nil, nil, [], catalog, []) == nil)
    }

    private func resolve(
        _ saved: String?,
        _ last: String?,
        _ visible: [ProviderInstanceID],
        _ catalog: [ProviderInstanceID],
        _ configured: Set<ProviderInstanceID>) -> ProviderInstanceID?
    {
        TokenTrackerProviderSelection.resolve(
            savedID: saved,
            lastOpenedID: last,
            visibleProviderIDs: visible,
            catalogProviderIDs: catalog,
            configuredProviderIDs: configured)
    }
}
