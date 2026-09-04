import CodexBarCore
import Foundation

struct TokenTrackerProviderCatalogEntry: Identifiable, Equatable {
    enum Source: Equatable {
        case firstParty(UsageProvider)
        case plugin
    }

    let id: ProviderInstanceID
    let displayName: String
    let icon: TokenTrackerProviderIcon
    let accent: ProviderColor
    let source: Source
    let balanceOnly: Bool
}

enum TokenTrackerProviderIcon: Equatable {
    case resource(name: String, style: String)
    case monogram(String)
}

struct TokenTrackerProviderItem: Identifiable, Equatable {
    let id: ProviderInstanceID
    let displayName: String
    let icon: TokenTrackerProviderIcon
    let accent: ProviderColor
    let primaryMetric: TokenTrackerProviderMetric
    let secondaryMetrics: [TokenTrackerMetricRow]
    let detailSections: [ProviderDetailSection]
    let detailKind: TokenTrackerProviderDetailKind
    let detailBanner: String?
    let health: TokenTrackerProviderHealth
    let lastUpdatedAt: Date?
    let isEnabled: Bool
}

enum TokenTrackerProviderDetailKind: Equatable {
    case quota([TokenTrackerQuotaMeter])
    case balance(TokenTrackerBalanceSummary)
    case status(TokenTrackerStatusSummary)
}

struct TokenTrackerQuotaMeter: Equatable, Identifiable {
    let id: String
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
}

struct TokenTrackerBalanceSummary: Equatable {
    let valueText: String
    let subtitle: String
    let summaryRows: [TokenTrackerMetricRow]
    let chart: ProviderDetailSection.Chart?
    let updatedAt: Date?
}

struct TokenTrackerStatusSummary: Equatable {
    let message: String
    let isError: Bool
}

enum TokenTrackerProviderMetric: Equatable {
    case utilization(usedFraction: Double, resetsAt: Date?)
    case credits(remaining: Double, total: Double?, label: String?)
    case balance(amount: Double, currencyCode: String)
    case labeledValue(label: String, value: String)
    case status(String)
    case unavailable(String?)
}

struct TokenTrackerMetricRow: Equatable {
    let label: String
    let metric: TokenTrackerProviderMetric
}

enum TokenTrackerProviderHealth: Equatable {
    case healthy
    case refreshing
    case warning(String)
    case error(String)
    case unconfigured
}
