import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite("Token Tracker provider projection")
struct TokenTrackerProviderProjectionTests {
    @Test
    func `live catalog covers every first party provider in registry order`() {
        let catalog = TokenTrackerProviderProjection.liveCatalog()
        let firstPartyIDs = catalog.compactMap { entry -> ProviderInstanceID? in
            if case .firstParty = entry.source { entry.id } else { nil }
        }

        #expect(firstPartyIDs == ProviderDescriptorRegistry.all.map(\.id.instanceID))
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        #expect(firstPartyIDs.contains(.deepseek))
    }

    @Test
    func `highest real quota wins and remaining windows keep order`() {
        let now = Date()
        let snapshot = UsageSnapshot(
            primary: self.window(used: 40, reset: now.addingTimeInterval(300)),
            secondary: self.window(used: 80, reset: now.addingTimeInterval(600)),
            tertiary: self.window(used: 80, reset: now.addingTimeInterval(100)),
            extraRateWindows: [NamedRateWindow(
                id: "unknown",
                title: "Unknown",
                window: self.window(used: 99, reset: nil),
                usageKnown: false)],
            updatedAt: now)
        let item = self.item(snapshot: snapshot)

        #expect(item.primaryMetric == .utilization(remainingFraction: 0.2, resetsAt: now.addingTimeInterval(100)))
        #expect(item.secondaryMetrics.map(\.label) == ["Session", "Weekly"])
        guard case let .quota(meters) = item.detailKind else {
            Issue.record("Expected ordered quota detail")
            return
        }
        #expect(meters.map(\.label) == ["Session", "Weekly", "Tertiary"])
        #expect(meters.map(\.remainingFraction) == [0.6, 0.2, 0.2])
    }

    @Test
    func `metric priority uses total credits then balance then unbounded credits`() {
        let now = Date()
        let cost = ProviderCostSnapshot(
            used: 10,
            limit: 100,
            currencyCode: "USD",
            balance: 42,
            updatedAt: now)
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, providerCost: cost, updatedAt: now)
        let costItem = self.item(snapshot: snapshot)
        #expect(costItem.primaryMetric == .credits(remaining: 90, total: 100, label: nil))
        guard case let .quota(costMeters) = costItem.detailKind else {
            Issue.record("Expected provider cost quota detail")
            return
        }
        #expect(costMeters.map(\.remainingFraction) == [0.9])

        let balanceOnlyCost = ProviderCostSnapshot(
            used: 0,
            limit: 0,
            currencyCode: "USD",
            balance: 42,
            updatedAt: now)
        let balanceSnapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: balanceOnlyCost,
            updatedAt: now)
        let credits = CreditsSnapshot(remaining: 7, events: [], updatedAt: now)
        #expect(self.item(snapshot: balanceSnapshot, credits: credits).primaryMetric == .balance(
            amount: 42,
            currencyCode: "USD"))
        #expect(self.item(snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now), credits: credits)
            .primaryMetric == .credits(remaining: 7, total: nil, label: nil))
    }

    @Test
    func `disabled and errors expose honest health`() {
        let disabled = self.item(snapshot: nil, error: "stale", enabled: false)
        #expect(disabled.health == .unconfigured)
        #expect(disabled.primaryMetric == .unavailable("Unconfigured"))

        let failed = self.item(snapshot: nil, error: "refresh failed", enabled: true)
        #expect(failed.health == .error("refresh failed"))
        #expect(failed.primaryMetric == .status("refresh failed"))
        guard case let .status(disabledStatus) = disabled.detailKind else {
            Issue.record("Expected disabled status detail")
            return
        }
        #expect(disabledStatus.message == "Unconfigured")
        guard case let .status(failedStatus) = failed.detailKind else {
            Issue.record("Expected error status detail")
            return
        }
        #expect(failedStatus.message == "refresh failed")
    }

    @Test
    func `balance only wins before quota and selects matching currency chart`() throws {
        let now = Date()
        let amountChart = try ProviderDetailSection.Chart(
            kind: .bars,
            title: "Daily spend",
            unit: " usd ",
            points: [
                ProviderDetailSection.Chart.Point(label: "Mon", value: 1),
                ProviderDetailSection.Chart.Point(label: "Tue", value: 2),
            ])
        let tokenChart = try ProviderDetailSection.Chart(
            kind: .bars,
            title: "Daily tokens",
            unit: "tokens",
            points: [ProviderDetailSection.Chart.Point(label: "Mon", value: 10)])
        let snapshot = try UsageSnapshot(
            primary: self.window(used: 90, reset: now),
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 10,
                limit: 100,
                currencyCode: "USD",
                balance: 42,
                updatedAt: now),
            details: [
                ProviderDetailSection(chart: tokenChart),
                ProviderDetailSection(chart: amountChart),
            ],
            updatedAt: now)
        let catalog = TokenTrackerProviderCatalogEntry(
            id: .deepseek,
            displayName: "DeepSeek",
            icon: .monogram("D"),
            accent: ProviderColor(hex: 0x000000),
            source: .firstParty(.deepseek),
            balanceOnly: true)
        let item = TokenTrackerProviderProjection.makeItem(
            catalog: catalog,
            state: TokenTrackerProviderState(
                snapshot: snapshot,
                credits: CreditsSnapshot(remaining: 7, events: [], updatedAt: now),
                error: nil,
                isRefreshing: false,
                statusWarning: nil,
                isEnabled: true),
            rateWindowLabels: ["Session", "Weekly", "Tertiary"])

        guard case let .balance(summary) = item.detailKind else {
            Issue.record("Expected balance detail")
            return
        }
        #expect(summary.valueText == "42 USD")
        #expect(summary.chart?.title == "Daily spend")
        #expect(summary.chart?.kind == .bars)
        #expect(summary.chart?.points.map(\.value) == [1, 2])
        #expect(item.primaryMetric == .balance(amount: 42, currencyCode: "USD"))
    }

    @Test
    func `balance chart falls back to first nonempty chart without currency`() throws {
        let chart = try ProviderDetailSection.Chart(
            kind: .bars,
            title: "Daily tokens",
            unit: "tokens",
            points: [ProviderDetailSection.Chart.Point(label: "Mon", value: 10)])
        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 0,
                limit: 0,
                currencyCode: "USD",
                balance: 42,
                updatedAt: Date()),
            details: [ProviderDetailSection(chart: chart)],
            updatedAt: Date())
        let item = self.item(snapshot: snapshot)

        guard case let .balance(summary) = item.detailKind else {
            Issue.record("Expected balance detail")
            return
        }
        #expect(summary.chart?.title == "Daily tokens")
        #expect(summary.chart?.points.count == 1)
    }

    @Test
    func `refreshing or warning keeps trusted data and adds a banner`() {
        let snapshot = UsageSnapshot(
            primary: self.window(used: 40, reset: nil),
            secondary: nil,
            updatedAt: Date())
        let refreshing = self.item(snapshot: snapshot, health: .refreshing)
        let warning = self.item(snapshot: snapshot, health: .warning("cached data"))

        #expect(refreshing.detailBanner == "Refreshing")
        #expect(warning.detailBanner == "cached data")
        if case .quota = refreshing.detailKind {} else {
            Issue.record("Refreshing data should remain quota detail")
        }
        if case .quota = warning.detailKind {} else {
            Issue.record("Warning data should remain quota detail")
        }
    }

    @Test
    func `synthetic or invalid quota windows do not fabricate a meter`() {
        let placeholder = RateWindow(
            usedPercent: 0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil,
            isSyntheticPlaceholder: true)
        let invalid = self.window(used: .nan, reset: nil)
        let snapshot = UsageSnapshot(primary: placeholder, secondary: invalid, updatedAt: Date())
        let item = self.item(snapshot: snapshot)

        guard case .status = item.detailKind else {
            Issue.record("Expected status when no real quota is available")
            return
        }
        #expect(item.primaryMetric == .unavailable(nil))
    }

    private func item(
        snapshot: UsageSnapshot?,
        credits: CreditsSnapshot? = nil,
        error: String? = nil,
        enabled: Bool = true,
        health: TokenTrackerProviderHealth? = nil) -> TokenTrackerProviderItem
    {
        let isRefreshing = health == .refreshing
        let statusWarning: String? = if case let .warning(message) = health { message } else { nil }
        let effectiveError: String? = if case let .error(message) = health { message } else { error }
        return TokenTrackerProviderProjection.makeItem(
            catalog: TokenTrackerProviderCatalogEntry(
                id: .codex,
                displayName: "Codex",
                icon: .monogram("C"),
                accent: ProviderColor(hex: 0x000000),
                source: .firstParty(.codex),
                balanceOnly: false),
            state: TokenTrackerProviderState(
                snapshot: snapshot,
                credits: credits,
                error: effectiveError,
                isRefreshing: isRefreshing,
                statusWarning: statusWarning,
                isEnabled: enabled),
            rateWindowLabels: ["Session", "Weekly", "Tertiary"])
    }

    private func window(used: Double, reset: Date?) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: nil, resetsAt: reset, resetDescription: nil)
    }
}
