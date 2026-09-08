import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@Suite("Token Tracker accessibility")
struct TokenTrackerAccessibilityTests {
    @Test(arguments: [
        (TokenTrackerProviderMetric.utilization(remainingFraction: 0.58, resetsAt: nil), "58% remaining", "healthy"),
        (.credits(remaining: 7, total: 10, label: "API credits"), "7/10 · API credits", "healthy"),
        (.balance(amount: 12.5, currencyCode: "USD"), "Balance · 12.5 USD", "healthy"),
        (.unavailable("Sign in required"), "Sign in required", "unconfigured"),
    ])
    func `provider label includes name primary metric and health`(
        metric: TokenTrackerProviderMetric,
        expectedMetric: String,
        expectedHealth: String)
    {
        let health: TokenTrackerProviderHealth = expectedHealth == "healthy" ? .healthy : .unconfigured
        let label = TokenTrackerAccessibility.providerLabel(self.item(metric: metric, health: health))
        #expect(label.contains("Codex"))
        #expect(label.contains(expectedMetric))
        #expect(label.contains(expectedHealth))
    }

    @Test(arguments: [
        (TokenTrackerProviderHealth.refreshing, "refreshing"),
        (.warning("Nearly empty"), "warning, Nearly empty"),
        (.error("Refresh failed"), "error, Refresh failed"),
        (.unconfigured, "unconfigured"),
    ])
    func `provider label announces every nonhealthy state`(
        health: TokenTrackerProviderHealth,
        expected: String)
    {
        let label = TokenTrackerAccessibility.providerLabel(self.item(
            metric: .status("Waiting"),
            health: health))
        #expect(label.contains(expected))
    }

    @Test
    func `provider click actions have distinct hints`() {
        #expect(TokenTrackerAccessibility.providerActionHint(.showDetail) == "Show provider details")
        #expect(TokenTrackerAccessibility.providerActionHint(.togglePinnedDetail) == "Toggle pinned provider details")
        #expect(TokenTrackerAccessibility.providerActionHint(.openProviderSettings) == "Open provider settings")
    }

    @Test
    func `increased contrast strengthens every low contrast surface token`() {
        let normal = TokenTrackerSurfaceVisualStyle(contrast: .standard)
        let increased = TokenTrackerSurfaceVisualStyle(contrast: .increased)

        #expect(increased.outlineOpacity > normal.outlineOpacity)
        #expect(increased.handleOutlineOpacity > normal.handleOutlineOpacity)
        #expect(increased.inactiveTileOpacity > normal.inactiveTileOpacity)
        #expect(increased.hoveredTileOpacity > normal.hoveredTileOpacity)
        #expect(increased.dividerOpacity > normal.dividerOpacity)
    }

    private func item(
        metric: TokenTrackerProviderMetric,
        health: TokenTrackerProviderHealth) -> TokenTrackerProviderItem
    {
        TokenTrackerProviderItem(
            id: .codex,
            displayName: "Codex",
            icon: .monogram("C"),
            accent: ProviderColor(hex: 0xFFFFFF),
            primaryMetric: metric,
            secondaryMetrics: [],
            detailSections: [],
            detailKind: .status(TokenTrackerStatusSummary(message: "Usage unavailable", isError: false)),
            detailBanner: nil,
            health: health,
            lastUpdatedAt: nil,
            isEnabled: true)
    }
}
