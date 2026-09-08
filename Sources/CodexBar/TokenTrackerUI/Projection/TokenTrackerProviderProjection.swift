import CodexBarCore
import Foundation
import Observation

@MainActor
@Observable
final class TokenTrackerProviderProjection {
    @ObservationIgnored private let store: UsageStore
    @ObservationIgnored private let settings: SettingsStore

    init(store: UsageStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    var catalog: [TokenTrackerProviderCatalogEntry] {
        _ = self.settings.tokenTrackerPreferences.catalogRevision
        return Self.liveCatalog()
    }

    var visibleItems: [TokenTrackerProviderItem] {
        let catalog = self.catalog
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return self.settings.tokenTrackerPreferences.effectiveVisibleProviderIDs.compactMap { id in
            byID[id].map(self.makeLiveItem)
        }
    }

    var configuredProviderIDs: Set<ProviderInstanceID> {
        Set(self.catalog.compactMap { entry in
            self.isEnabled(entry) ? entry.id : nil
        })
    }

    func reconcileCatalog() {
        self.settings.tokenTrackerPreferences.reconcileAvailableProviderIDs(self.catalog.map(\.id))
    }

    func resolveProvider(savedID: String?, lastOpenedID: String?) -> ProviderInstanceID? {
        TokenTrackerProviderSelection.resolve(
            savedID: savedID,
            lastOpenedID: lastOpenedID,
            visibleProviderIDs: self.settings.tokenTrackerPreferences.effectiveVisibleProviderIDs,
            catalogProviderIDs: self.catalog.map(\.id),
            configuredProviderIDs: self.configuredProviderIDs)
    }

    static func liveCatalog() -> [TokenTrackerProviderCatalogEntry] {
        var seen = Set<ProviderInstanceID>()
        var catalog: [TokenTrackerProviderCatalogEntry] = []
        for descriptor in ProviderDescriptorRegistry.all {
            let id = descriptor.id.instanceID
            guard seen.insert(id).inserted else { continue }
            catalog.append(TokenTrackerProviderCatalogEntry(
                id: id,
                displayName: descriptor.metadata.displayName,
                icon: .resource(
                    name: descriptor.branding.iconResourceName,
                    style: descriptor.branding.iconStyle.rawValue),
                accent: ProviderAccentPalette.color(for: descriptor.id),
                source: .firstParty(descriptor.id),
                balanceOnly: descriptor.metadata.balanceOnly))
        }
        for plugin in UserProviderPluginRegistry.all {
            let manifest = plugin.manifest
            guard seen.insert(manifest.id).inserted else { continue }
            catalog.append(TokenTrackerProviderCatalogEntry(
                id: manifest.id,
                displayName: manifest.name,
                icon: .monogram(manifest.icon.monogram),
                accent: ProviderColor(hexString: manifest.icon.tint) ?? ProviderColor(hex: 0x8E8E93),
                source: .plugin,
                balanceOnly: false))
        }
        return catalog
    }

    static func makeItem(
        catalog: TokenTrackerProviderCatalogEntry,
        state: TokenTrackerProviderState,
        rateWindowLabels: [String]) -> TokenTrackerProviderItem
    {
        let health: TokenTrackerProviderHealth = if !state.isEnabled {
            .unconfigured
        } else if state.isRefreshing {
            .refreshing
        } else if let error = state.error {
            .error(error)
        } else if let statusWarning = state.statusWarning {
            .warning(statusWarning)
        } else {
            .healthy
        }
        let metrics = Self.metrics(
            snapshot: state.snapshot,
            credits: state.credits,
            balanceOnly: catalog.balanceOnly,
            health: health,
            rateWindowLabels: rateWindowLabels)
        let detail = Self.detailProjection(
            snapshot: state.snapshot,
            credits: state.credits,
            balanceOnly: catalog.balanceOnly,
            health: health,
            rateWindowLabels: rateWindowLabels)
        let dates = [state.snapshot?.updatedAt, state.snapshot?.providerCost?.updatedAt, state.credits?.updatedAt]
            .compactMap(\.self)
        return TokenTrackerProviderItem(
            id: catalog.id,
            displayName: catalog.displayName,
            icon: catalog.icon,
            accent: catalog.accent,
            primaryMetric: metrics.primary,
            secondaryMetrics: metrics.secondary,
            detailSections: state.snapshot?.details ?? [],
            detailKind: detail.kind,
            detailBanner: detail.banner,
            health: health,
            lastUpdatedAt: dates.max(),
            isEnabled: state.isEnabled)
    }
}

extension TokenTrackerProviderProjection {
    private struct DetailProjection {
        let kind: TokenTrackerProviderDetailKind
        let banner: String?
    }

    private struct WindowCandidate {
        let id: String
        let index: Int
        let label: String
        let window: RateWindow
    }

    private func makeLiveItem(_ catalog: TokenTrackerProviderCatalogEntry) -> TokenTrackerProviderItem {
        let snapshot: UsageSnapshot?
        let error: String?
        let labels: [String]
        let statusWarning: String?
        switch catalog.source {
        case let .firstParty(provider):
            snapshot = self.store.presentationSnapshot(for: provider)
            error = self.store.userFacingError(for: provider)
            if let snapshot {
                let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
                let resolved = descriptor.presentation.rateWindowLabels(
                    metadata: descriptor.metadata,
                    snapshot: snapshot)
                labels = [resolved.primary, resolved.secondary, resolved.tertiary]
            } else {
                let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
                labels = [metadata.sessionLabel, metadata.weeklyLabel, metadata.opusLabel ?? "Tertiary"]
            }
            if let status = self.store.status(for: provider), status.indicator.hasIssue {
                statusWarning = status.description ?? status.indicator.label
            } else {
                statusWarning = nil
            }
        case .plugin:
            snapshot = self.store.snapshot(for: catalog.id)
            error = self.store.errors[catalog.id]
            labels = ["Primary", "Secondary", "Tertiary"]
            statusWarning = nil
        }
        // Provider-specific by design: UsageStore exposes a separate credits stream only for Codex.
        let credits = catalog.id == .codex ? self.store.credits : nil
        return Self.makeItem(
            catalog: catalog,
            state: TokenTrackerProviderState(
                snapshot: snapshot,
                credits: credits,
                error: error,
                isRefreshing: self.store.refreshingProviders.contains(catalog.id),
                statusWarning: statusWarning,
                isEnabled: self.isEnabled(catalog)),
            rateWindowLabels: labels)
    }

    private func isEnabled(_ entry: TokenTrackerProviderCatalogEntry) -> Bool {
        switch entry.source {
        case let .firstParty(provider):
            let metadata = ProviderDescriptorRegistry.descriptor(for: provider).metadata
            return self.settings.isProviderEnabled(provider: provider, metadata: metadata)
        case .plugin:
            return self.settings.isPluginEnabled(entry.id)
        }
    }

    private static func metrics(
        snapshot: UsageSnapshot?,
        credits: CreditsSnapshot?,
        balanceOnly: Bool,
        health: TokenTrackerProviderHealth,
        rateWindowLabels: [String]) -> (primary: TokenTrackerProviderMetric, secondary: [TokenTrackerMetricRow])
    {
        guard health != .unconfigured else {
            return (.unavailable(healthMessage(health)), [])
        }
        if case .error = health, snapshot == nil {
            return (.status(healthMessage(health) ?? "Usage unavailable"), [])
        }
        if case .warning = health, snapshot == nil {
            return (.status(healthMessage(health) ?? "Usage unavailable"), [])
        }
        if health == .refreshing, snapshot == nil {
            return (.status(healthMessage(health) ?? "Usage unavailable"), [])
        }
        guard let snapshot else {
            if let creditsMetric = creditsMetric(credits) {
                return (creditsMetric, [])
            }
            return (.unavailable(Self.healthMessage(health)), [])
        }

        let windows = Self.windows(snapshot: snapshot, labels: rateWindowLabels)
        let validWindows = balanceOnly ? [] : windows.filter { candidate in
            candidate.window.isSyntheticPlaceholder == false && candidate.window.usedPercent.isFinite
        }
        let selected = validWindows.max { lhs, rhs in
            let left = UsagePercent(raw: lhs.window.usedPercent).displayClamped
            let right = UsagePercent(raw: rhs.window.usedPercent).displayClamped
            if left != right { return left < right }
            return (lhs.window.resetsAt ?? .distantFuture) > (rhs.window.resetsAt ?? .distantFuture)
        }
        if let selected {
            let primary = TokenTrackerProviderMetric.utilization(
                remainingFraction: UsagePercent(raw: selected.window.remainingPercent).displayClamped / 100,
                resetsAt: selected.window.resetsAt)
            let secondary = validWindows.filter { $0.index != selected.index }.map { candidate in
                TokenTrackerMetricRow(
                    label: candidate.label,
                    metric: .utilization(
                        remainingFraction: UsagePercent(raw: candidate.window.remainingPercent).displayClamped / 100,
                        resetsAt: candidate.window.resetsAt))
            }
            return (primary, secondary)
        }

        if !balanceOnly, let cost = snapshot.providerCost, cost.limit.isFinite, cost.limit > 0 {
            return (.credits(
                remaining: max(0, cost.limit - cost.used),
                total: cost.limit,
                label: cost.period), [])
        }
        if !balanceOnly, let creditLimit = credits?.codexCreditLimit, creditLimit.limit > 0 {
            return (.credits(
                remaining: creditLimit.remaining,
                total: creditLimit.limit,
                label: creditLimit.title), [])
        }
        if let cost = snapshot.providerCost, let balance = cost.balance, balance.isFinite {
            return (.balance(amount: balance, currencyCode: cost.currencyCode), [])
        }
        if let credits {
            return (.credits(remaining: credits.remaining, total: nil, label: nil), [])
        }
        if balanceOnly, let description = snapshot.primary?.resetDescription, !description.isEmpty {
            return (.labeledValue(label: "Balance", value: description), [])
        }
        if let healthMessage = Self.healthMessage(health) {
            return (.status(healthMessage), [])
        }
        return (.unavailable(nil), [])
    }

    private static func detailProjection(
        snapshot: UsageSnapshot?,
        credits: CreditsSnapshot?,
        balanceOnly: Bool,
        health: TokenTrackerProviderHealth,
        rateWindowLabels: [String]) -> DetailProjection
    {
        if health == .unconfigured {
            return self.statusProjection(for: health)
        }
        guard let snapshot else {
            return self.statusProjection(for: health)
        }

        let windows = self.windows(snapshot: snapshot, labels: rateWindowLabels)
        let realWindows = windows.filter { candidate in
            candidate.window.isSyntheticPlaceholder == false
                && candidate.window.usedPercent.isFinite
        }

        if !balanceOnly, !realWindows.isEmpty {
            let meters = realWindows.map { candidate in
                TokenTrackerQuotaMeter(
                    id: candidate.id,
                    label: candidate.label,
                    remainingFraction: Self.fraction(percent: candidate.window.remainingPercent),
                    resetsAt: candidate.window.resetsAt)
            }
            return self.dataProjection(kind: .quota(meters), health: health)
        }

        if !balanceOnly, let cost = snapshot.providerCost,
           cost.limit.isFinite, cost.limit > 0,
           cost.used.isFinite
        {
            let meter = TokenTrackerQuotaMeter(
                id: "provider-cost",
                label: cost.period ?? "Usage",
                remainingFraction: Self.fraction(value: max(0, cost.limit - cost.used), total: cost.limit),
                resetsAt: cost.resetsAt)
            return self.dataProjection(kind: .quota([meter]), health: health)
        }

        if !balanceOnly, let limit = credits?.codexCreditLimit,
           limit.limit.isFinite, limit.limit > 0
        {
            let meter = TokenTrackerQuotaMeter(
                id: "codex-credit-limit",
                label: limit.title,
                remainingFraction: Self.fraction(value: limit.remaining, total: limit.limit),
                resetsAt: limit.resetsAt)
            return self.dataProjection(kind: .quota([meter]), health: health)
        }

        if let cost = snapshot.providerCost,
           let balance = cost.balance,
           balance.isFinite
        {
            return self.dataProjection(
                kind: .balance(self.balanceSummary(
                    valueText: self.amountText(balance, currencyCode: cost.currencyCode),
                    snapshot: snapshot,
                    currencyCode: cost.currencyCode)),
                health: health)
        }

        if let credits, credits.remaining.isFinite {
            return self.dataProjection(
                kind: .balance(self.balanceSummary(
                    valueText: self.numberText(credits.remaining),
                    snapshot: snapshot,
                    currencyCode: nil)),
                health: health)
        }

        if balanceOnly,
           let description = snapshot.primary?.resetDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return self.dataProjection(
                kind: .balance(self.balanceSummary(
                    valueText: description,
                    snapshot: snapshot,
                    currencyCode: nil)),
                health: health)
        }

        return self.statusProjection(for: health)
    }

    private static func dataProjection(
        kind: TokenTrackerProviderDetailKind,
        health: TokenTrackerProviderHealth) -> DetailProjection
    {
        let banner: String? = switch health {
        case .refreshing: "Refreshing"
        case let .warning(message), let .error(message): message
        case .healthy, .unconfigured: nil
        }
        return DetailProjection(kind: kind, banner: banner)
    }

    private static func statusProjection(
        for health: TokenTrackerProviderHealth) -> DetailProjection
    {
        let message = Self.healthMessage(health) ?? "Usage unavailable"
        let isError = switch health {
        case .error: true
        case .healthy, .refreshing, .warning, .unconfigured: false
        }
        return DetailProjection(
            kind: .status(TokenTrackerStatusSummary(message: message, isError: isError)),
            banner: nil)
    }

    private static func balanceSummary(
        valueText: String,
        snapshot: UsageSnapshot,
        currencyCode: String?) -> TokenTrackerBalanceSummary
    {
        let summaryRows = snapshot.details.flatMap(\.rows).map { row in
            let value = if let secondaryValue = row.secondaryValue {
                "\(row.value) · \(secondaryValue)"
            } else {
                row.value
            }
            return TokenTrackerMetricRow(
                label: row.label,
                metric: .labeledValue(label: row.label, value: value))
        }
        return TokenTrackerBalanceSummary(
            valueText: valueText,
            subtitle: "Available balance",
            summaryRows: summaryRows,
            chart: Self.balanceChart(in: snapshot.details, currencyCode: currencyCode),
            updatedAt: snapshot.updatedAt)
    }

    private static func balanceChart(
        in sections: [ProviderDetailSection],
        currencyCode: String?) -> ProviderDetailSection.Chart?
    {
        let charts = sections.compactMap(\.chart).filter { !$0.points.isEmpty }
        guard !charts.isEmpty else { return nil }
        let selected: ProviderDetailSection.Chart = if let currencyCode {
            charts.first { chart in
                guard let unit = chart.unit else { return false }
                return unit.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)) ==
                    .orderedSame
            } ?? charts[0]
        } else {
            charts[0]
        }
        let matchesCurrency = if let currencyCode, let unit = selected.unit {
            unit.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        } else {
            false
        }
        return try? ProviderDetailSection.Chart(
            kind: .bars,
            title: matchesCurrency ? "Daily spend" : selected.title,
            unit: selected.unit,
            points: selected.points)
    }

    private static func fraction(percent: Double) -> Double {
        self.fraction(value: percent, total: 100)
    }

    private static func fraction(value: Double, total: Double) -> Double {
        guard value.isFinite, total.isFinite, total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    private static func amountText(_ amount: Double, currencyCode: String) -> String {
        "\(self.numberText(amount)) \(currencyCode)"
    }

    private static func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func windows(snapshot: UsageSnapshot, labels: [String]) -> [WindowCandidate] {
        var result: [WindowCandidate] = []
        for (index, window) in [snapshot.primary, snapshot.secondary, snapshot.tertiary].enumerated() {
            guard let window else { continue }
            let label = labels.indices.contains(index) ? labels[index] : "Window \(index + 1)"
            result.append(WindowCandidate(id: "window-\(index)", index: index, label: label, window: window))
        }
        for named in snapshot.extraRateWindows ?? [] where named.usageKnown {
            result.append(WindowCandidate(
                id: named.id,
                index: result.count + 3,
                label: named.title,
                window: named.window))
        }
        return result
    }

    private static func creditsMetric(_ credits: CreditsSnapshot?) -> TokenTrackerProviderMetric? {
        guard let credits else { return nil }
        if let limit = credits.codexCreditLimit, limit.limit > 0 {
            return .credits(remaining: limit.remaining, total: limit.limit, label: limit.title)
        }
        return .credits(remaining: credits.remaining, total: nil, label: nil)
    }

    private static func healthMessage(_ health: TokenTrackerProviderHealth) -> String? {
        switch health {
        case .healthy: nil
        case .refreshing: "Refreshing"
        case let .warning(message), let .error(message): message
        case .unconfigured: "Unconfigured"
        }
    }
}

struct TokenTrackerProviderState {
    let snapshot: UsageSnapshot?
    let credits: CreditsSnapshot?
    let error: String?
    let isRefreshing: Bool
    let statusWarning: String?
    let isEnabled: Bool
}
