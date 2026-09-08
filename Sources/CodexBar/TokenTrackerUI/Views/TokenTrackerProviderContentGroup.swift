import SwiftUI

@MainActor
struct TokenTrackerProviderContentGroup: View {
    let item: TokenTrackerProviderItem
    let slot: CGFloat
    let mode: TokenTrackerPresentationMode
    let anchorStore: TokenTrackerProviderAnchorStore

    var body: some View {
        VStack(spacing: self.gap) {
            if self.mode == .side {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.9))
                        .frame(width: self.logoSize + 8, height: self.logoSize + 8)
                    self.logo
                }
            } else {
                self.logo
            }
            if self.showsMetric {
                Text(self.metricText)
                    .font(.system(size: self.metricFontSize, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var logo: some View {
        if self.slot < 12 {
            Circle()
                .fill(self.accent)
                .frame(width: max(self.slot * 0.45, 1), height: max(self.slot * 0.45, 1))
                .background { self.anchorReporter }
        } else {
            ZStack(alignment: .topTrailing) {
                TokenTrackerProviderIconRing(
                    item: self.item,
                    compact: self.slot < 52,
                    iconScale: self.mode == .side ? 1.20 : 1)
                    .frame(width: self.logoSize, height: self.logoSize)
                    .background { self.anchorReporter }
                if self.hasIssue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: max(self.slot * 0.16, 3)))
                        .foregroundStyle(.orange)
                        .offset(x: self.logoSize * 0.18, y: -self.logoSize * 0.14)
                }
            }
        }
    }

    private var anchorReporter: some View {
        TokenTrackerProviderAnchorReporter(
            mode: self.mode,
            providerID: self.item.id,
            logoCenter: nil,
            onUpdate: { anchor in
                self.anchorStore.update(
                    mode: self.mode,
                    providerID: self.item.id,
                    tileFrame: anchor.tileFrame,
                    logoCenter: anchor.logoCenter,
                    surfaceVisibleFrame: anchor.surfaceVisibleFrame)
            })
            .allowsHitTesting(false)
    }

    private var logoSize: CGFloat {
        if self.mode == .side {
            return max(self.slot * 31 / 56, 5)
        }
        return max(self.slot * 28 / 64, 5)
    }

    private var gap: CGFloat {
        if self.mode == .side {
            return max(self.slot * 2 / 56, 0)
        }
        return max(self.slot * 4 / 64, 0)
    }

    private var metricFontSize: CGFloat {
        if self.mode == .side {
            return max(self.slot * 9 / 56, 3)
        }
        return max(self.slot * 9 / 64, 3)
    }

    private var showsMetric: Bool {
        guard self.slot >= 36 else { return false }
        if self.mode == .side, case .unavailable = self.item.primaryMetric {
            return false
        }
        return true
    }

    private var metricText: String {
        if case .unavailable = self.item.primaryMetric { return "—" }
        let metric = TokenTrackerMetricFormatter.short(self.item.primaryMetric)
        for separator in ["(", " / ", " · "] {
            if let range = metric.range(of: separator) {
                return String(metric[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return metric
    }

    private var hasIssue: Bool {
        switch self.item.health {
        case .warning, .error, .unconfigured: true
        case .healthy, .refreshing: false
        }
    }

    private var accent: Color {
        Color(red: self.item.accent.red, green: self.item.accent.green, blue: self.item.accent.blue)
    }
}
