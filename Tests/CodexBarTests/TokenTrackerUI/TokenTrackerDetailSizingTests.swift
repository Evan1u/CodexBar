import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@Suite("Token Tracker detail sizing")
struct TokenTrackerDetailSizingTests {
    @Test
    func `intrinsic body height is bounded by the visible screen`() {
        #expect(TokenTrackerDetailSizing.bodyHeight(fittingHeight: 212, visibleHeight: 900) == 212)
        #expect(TokenTrackerDetailSizing.bodyHeight(fittingHeight: 600, visibleHeight: 900) == 400)
        #expect(TokenTrackerDetailSizing.bodyHeight(fittingHeight: 212, visibleHeight: 200) == 176)
    }

    @Test
    func `side and bottom apply the arrow only on its attachment axis`() {
        #expect(TokenTrackerDetailSizing.sideSize(bodyHeight: 212) == CGSize(width: 374, height: 212))
        #expect(TokenTrackerDetailSizing.bottomSize(bodyHeight: 212) == CGSize(width: 360, height: 226))
    }

    @MainActor
    @Test
    func `two quota meters fit the target detail body height`() {
        let item = TokenTrackerProviderItem(
            id: .codex,
            displayName: "Codex",
            icon: .monogram("C"),
            accent: ProviderColor(hex: 0x000000),
            primaryMetric: .utilization(usedFraction: 0.4, resetsAt: nil),
            secondaryMetrics: [],
            detailSections: [],
            detailKind: .quota([
                TokenTrackerQuotaMeter(id: "session", label: "Current session", usedFraction: 0.4, resetsAt: nil),
                TokenTrackerQuotaMeter(id: "weekly", label: "Weekly", usedFraction: 0.8, resetsAt: nil),
            ]),
            detailBanner: nil,
            health: .healthy,
            lastUpdatedAt: nil,
            isEnabled: true)
        let host = NSHostingView(rootView: TokenTrackerNotchDetailView(
            item: item,
            onRefresh: {},
            onClose: {},
            onOpenSettings: {}))
        host.frame = NSRect(x: 0, y: 0, width: TokenTrackerDetailSizing.bodyWidth, height: 1)
        host.layoutSubtreeIfNeeded()

        let height = ceil(host.fittingSize.height)
        #expect((190...260).contains(height))
    }

    @MainActor
    @Test
    func `DeepSeek balance detail fits its rows and chart without cap clipping`() throws {
        let chart = try ProviderDetailSection.Chart(
            kind: .bars,
            title: "Daily tokens",
            unit: "tokens",
            points: [
                .init(label: "Mon", value: 1),
                .init(label: "Tue", value: 2),
            ])
        let rows = [
            "Today", "This month", "Requests", "Top model",
            "Cache-hit input", "Cache-miss input", "Output",
        ].map { label in
            TokenTrackerMetricRow(label: label, metric: .labeledValue(label: label, value: "123,456 tokens"))
        }
        let item = TokenTrackerProviderItem(
            id: .deepseek,
            displayName: "DeepSeek",
            icon: .monogram("D"),
            accent: ProviderColor(hex: 0x4D6BFE),
            primaryMetric: .balance(amount: 38.54, currencyCode: "CNY"),
            secondaryMetrics: [],
            detailSections: [],
            detailKind: .balance(TokenTrackerBalanceSummary(
                valueText: "¥38.54",
                subtitle: "Available balance",
                summaryRows: rows,
                chart: chart,
                updatedAt: nil)),
            detailBanner: nil,
            health: .healthy,
            lastUpdatedAt: nil,
            isEnabled: true)
        let host = NSHostingView(rootView: TokenTrackerNotchDetailView(
            item: item,
            onRefresh: {},
            onClose: {},
            onOpenSettings: {}))
        host.frame = NSRect(x: 0, y: 0, width: TokenTrackerDetailSizing.bodyWidth, height: 1)
        host.layoutSubtreeIfNeeded()

        let height = ceil(host.fittingSize.height)
        #expect((361...400).contains(height))
        #expect(TokenTrackerDetailSizing.bodyHeight(fittingHeight: height, visibleHeight: 900) == height)
    }
}
