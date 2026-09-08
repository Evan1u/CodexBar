import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct TokenTrackerNotchView: View {
    @Bindable var projection: TokenTrackerProviderProjection
    @Bindable var interaction: TokenTrackerNotchInteractionModel
    let preferences: TokenTrackerPreferencesStore
    let openTokenTrackerSettings: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            self.compactSurface
                .frame(height: 38)

            if self.interaction.isOverviewVisible {
                Divider().overlay(.white.opacity(self.visualStyle.dividerOpacity))
                self.overview
                    .transition(self.reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if let detailItem = self.detailItem {
                Divider().overlay(.white.opacity(self.visualStyle.dividerOpacity))
                TokenTrackerNotchDetailView(
                    item: detailItem,
                    onRefresh: self.interaction.requestRefresh,
                    onClose: self.interaction.closeDetail,
                    onOpenSettings: self.openTokenTrackerSettings)
                    .transition(self.reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                .fill(.black.opacity(0.96))
                .overlay {
                    UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                        .stroke(.white.opacity(self.visualStyle.outlineOpacity), lineWidth: 1)
                }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .animation(
            self.reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22),
            value: self.interaction.state)
    }

    private var compactSurface: some View {
        HStack(spacing: 6) {
            if let defaultItem = self.defaultItem {
                Button {
                    self.interaction.providerClicked(defaultItem.id)
                } label: {
                    TokenTrackerProviderIndicator(item: defaultItem, compact: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TokenTrackerAccessibility.providerLabel(defaultItem))
                .accessibilityHint(TokenTrackerAccessibility.providerActionHint(
                    self.preferences.preferences.notch.providerClickAction))
            } else {
                Label("No visible providers", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button(action: self.interaction.triggerClicked) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: self.interaction.isOverviewVisible ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(self.preferences.preferences.notch.openAction == .none)
            .accessibilityLabel("Show provider overview")
        }
        .padding(.horizontal, 10)
        .background {
            TokenTrackerNativeHoverRegion(
                onEnter: self.interaction.pointerEnteredTrigger,
                onExit: self.interaction.pointerExitedTrigger)
        }
    }

    private var overview: some View {
        Group {
            if self.projection.visibleItems.isEmpty {
                ContentUnavailableView(
                    "No visible providers",
                    systemImage: "eye.slash",
                    description: Text("Choose providers in Token Tracker settings."))
                    .frame(maxWidth: .infinity, minHeight: 78)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(self.projection.visibleItems) { item in
                            Button {
                                self.interaction.providerClicked(item.id)
                            } label: {
                                TokenTrackerProviderIndicator(item: item, compact: false)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        self.interaction.hoveredProviderID == item.id
                                            ? Color.white.opacity(self.visualStyle.hoveredTileOpacity)
                                            : Color.white.opacity(self.visualStyle.inactiveTileOpacity),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                self.interaction.providerHovered(hovering ? item.id : nil)
                            }
                            .accessibilityLabel(TokenTrackerAccessibility.providerLabel(item))
                            .accessibilityHint(TokenTrackerAccessibility.providerActionHint(
                                self.preferences.preferences.notch.providerClickAction))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(height: 92)
        .background {
            TokenTrackerNativeHoverRegion(
                onEnter: self.interaction.pointerEnteredProviderSurface,
                onExit: self.interaction.pointerExitedProviderSurface)
        }
    }

    private var defaultItem: TokenTrackerProviderItem? {
        let notch = self.preferences.preferences.notch
        guard let id = self.projection.resolveProvider(
            savedID: notch.defaultProviderID,
            lastOpenedID: notch.lastOpenedProviderID)
        else { return nil }
        return self.projection.visibleItems.first { $0.id == id }
    }

    private var detailItem: TokenTrackerProviderItem? {
        guard case let .detail(providerID, _) = self.interaction.state else { return nil }
        return self.projection.visibleItems.first { $0.id == providerID }
    }

    private var visualStyle: TokenTrackerSurfaceVisualStyle {
        TokenTrackerSurfaceVisualStyle(contrast: self.contrast)
    }
}

struct TokenTrackerProviderIndicator: View {
    let item: TokenTrackerProviderItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            TokenTrackerProviderIconRing(item: self.item, compact: self.compact)
                .frame(width: self.compact ? 24 : 30, height: self.compact ? 24 : 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(self.item.displayName)
                    .font(.system(size: self.compact ? 11 : 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(TokenTrackerMetricFormatter.short(self.item.primaryMetric))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct TokenTrackerProviderIconRing: View {
    let item: TokenTrackerProviderItem
    let compact: Bool
    let iconScale: CGFloat

    init(item: TokenTrackerProviderItem, compact: Bool, iconScale: CGFloat = 1) {
        self.item = item
        self.compact = compact
        self.iconScale = iconScale
    }

    var body: some View {
        ZStack {
            Circle().stroke(self.accent.opacity(0.30), lineWidth: 3)
            if case let .utilization(remainingFraction, _) = self.item.primaryMetric {
                Circle()
                    .trim(from: 0, to: remainingFraction)
                    .stroke(self.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            self.icon
                .frame(width: self.iconSize, height: self.iconSize)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch self.item.icon {
        case .resource:
            if let provider = self.item.id.firstPartyProvider,
               let image = ProviderBrandIcon.image(for: provider)
            {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(String(self.item.displayName.prefix(1))).font(.caption.bold())
            }
        case let .monogram(value):
            Text(value).font(.system(size: self.iconSize * 0.72, weight: .bold))
        }
    }

    private var iconSize: CGFloat {
        (self.compact ? 13 : 16) * self.iconScale
    }

    private var accent: Color {
        Color(red: self.item.accent.red, green: self.item.accent.green, blue: self.item.accent.blue)
    }
}

struct TokenTrackerNotchDetailView: View {
    let item: TokenTrackerProviderItem
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                TokenTrackerProviderIconRing(item: self.item, compact: false)
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("\(self.item.displayName) provider logo")
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.item.displayName).font(.headline)
                    Text(TokenTrackerMetricFormatter.long(self.item.primaryMetric))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: self.onRefresh) {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh usage")
                Button(action: self.onClose) {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close provider details")
                Button(action: self.onOpenSettings) {
                    Image(systemName: "gearshape").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Token Tracker settings")
                .accessibilityHint("Open the Token Tracker settings pane")
            }

            if let banner = self.item.detailBanner {
                Label(banner, systemImage: self.bannerSymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(self.bannerColor)
            }

            self.detailContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch self.item.detailKind {
        case let .quota(meters):
            TokenTrackerQuotaDetailContent(meters: meters, accent: self.accent)
        case let .balance(summary):
            TokenTrackerBalanceDetailContent(summary: summary, accent: self.accent)
        case let .status(summary):
            TokenTrackerStatusDetailContent(summary: summary)
        }
    }

    private var bannerSymbol: String {
        switch self.item.health {
        case .refreshing: "arrow.clockwise"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .healthy, .unconfigured: "info.circle"
        }
    }

    private var bannerColor: Color {
        switch self.item.health {
        case .error: .red
        case .warning: .orange
        case .refreshing, .healthy, .unconfigured: .secondary
        }
    }

    private var accent: Color {
        Color(red: self.item.accent.red, green: self.item.accent.green, blue: self.item.accent.blue)
    }
}

private struct TokenTrackerQuotaDetailContent: View {
    let meters: [TokenTrackerQuotaMeter]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quota")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(self.meters) { meter in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(meter.label)
                            .font(.caption)
                        Spacer(minLength: 8)
                        Text(Self.percent(meter.remainingFraction))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: meter.remainingFraction)
                        .tint(self.accent)
                    if let resetsAt = meter.resetsAt {
                        Text("Resets " + resetsAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))% remaining"
    }
}

private struct TokenTrackerBalanceDetailContent: View {
    let summary: TokenTrackerBalanceSummary
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(self.summary.valueText)
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(self.summary.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(self.summary.summaryRows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(TokenTrackerMetricFormatter.short(row.metric)).monospacedDigit()
                }
                .font(.caption)
            }

            if let chart = self.summary.chart,
               let section = try? ProviderDetailSection(title: chart.title, chart: chart)
            {
                ProviderDetailSectionsContent(sections: [section], chartColor: self.accent)
            }
        }
    }
}

private struct TokenTrackerStatusDetailContent: View {
    let summary: TokenTrackerStatusSummary

    var body: some View {
        Label(self.summary.message, systemImage: self.summary.isError ? "xmark.octagon" : "info.circle")
            .font(.body.weight(.medium))
            .foregroundStyle(self.summary.isError ? .red : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum TokenTrackerMetricFormatter {
    static func short(_ metric: TokenTrackerProviderMetric) -> String {
        switch metric {
        case let .utilization(remainingFraction, _): "\(Int((remainingFraction * 100).rounded()))%"
        case let .credits(remaining, total, _):
            total.map { "\(Self.number(remaining))/\(Self.number($0))" } ?? Self.number(remaining)
        case let .balance(amount, currencyCode): "\(Self.number(amount)) \(currencyCode)"
        case let .labeledValue(_, value): value
        case let .status(value): value
        case .unavailable: "Unavailable"
        }
    }

    static func long(_ metric: TokenTrackerProviderMetric) -> String {
        switch metric {
        case let .utilization(remainingFraction, resetsAt):
            let remaining = "\(Int((remainingFraction * 100).rounded()))% remaining"
            return resetsAt.map {
                "\(remaining) · resets \($0.formatted(.relative(presentation: .named)))"
            } ?? remaining
        case let .credits(_, _, label):
            return label.map { "\(Self.short(metric)) · \($0)" } ?? Self.short(metric)
        case .balance: return "Balance · \(self.short(metric))"
        case let .labeledValue(label, value): return "\(label) · \(value)"
        case let .status(value): return value
        case let .unavailable(message): return message ?? "Usage unavailable"
        }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum TokenTrackerAccessibility {
    static func providerLabel(_ item: TokenTrackerProviderItem) -> String {
        "\(item.displayName), \(TokenTrackerMetricFormatter.long(item.primaryMetric)), \(self.health(item.health))"
    }

    static func providerActionHint(_ action: TokenTrackerProviderClickAction) -> String {
        switch action {
        case .showDetail: "Show provider details"
        case .togglePinnedDetail: "Toggle pinned provider details"
        case .openProviderSettings: "Open provider settings"
        }
    }

    private static func health(_ health: TokenTrackerProviderHealth) -> String {
        switch health {
        case .healthy: "healthy"
        case .refreshing: "refreshing"
        case let .warning(message): "warning, \(message)"
        case let .error(message): "error, \(message)"
        case .unconfigured: "unconfigured"
        }
    }
}

struct TokenTrackerNativeHoverRegion: NSViewRepresentable {
    let assumePointerInside: Bool
    let onEnter: @MainActor () -> Void
    let onExit: @MainActor () -> Void

    init(
        assumePointerInside: Bool = false,
        onEnter: @escaping @MainActor () -> Void,
        onExit: @escaping @MainActor () -> Void)
    {
        self.assumePointerInside = assumePointerInside
        self.onEnter = onEnter
        self.onExit = onExit
    }

    func makeNSView(context: Context) -> TokenTrackerHoverTrackingView {
        TokenTrackerHoverTrackingView(
            assumePointerInside: self.assumePointerInside,
            onEnter: self.onEnter,
            onExit: self.onExit)
    }

    func updateNSView(_ nsView: TokenTrackerHoverTrackingView, context: Context) {
        nsView.onEnter = self.onEnter
        nsView.onExit = self.onExit
    }
}

final class TokenTrackerHoverTrackingView: NSView {
    var onEnter: @MainActor () -> Void
    var onExit: @MainActor () -> Void
    private var shouldAssumePointerInside: Bool
    private var hoverTrackingArea: NSTrackingArea?

    init(
        assumePointerInside: Bool,
        onEnter: @escaping @MainActor () -> Void,
        onExit: @escaping @MainActor () -> Void)
    {
        self.shouldAssumePointerInside = assumePointerInside
        self.onEnter = onEnter
        self.onExit = onExit
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { self.removeTrackingArea(hoverTrackingArea) }
        var options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseEnteredAndExited]
        if self.shouldAssumePointerInside {
            options.insert(.assumeInside)
            self.shouldAssumePointerInside = false
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: options,
            owner: self,
            userInfo: nil)
        self.addTrackingArea(area)
        self.hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        self.onEnter()
    }

    override func mouseExited(with event: NSEvent) {
        self.onExit()
    }
}
