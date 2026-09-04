import AppKit

struct TokenTrackerProviderSurfaceMetrics: Equatable, Sendable {
    // Keep visible content balanced: the space beyond the first/last content
    // group is approximately the same as the clear space between two groups.
    static let providerPitchMultiplier: CGFloat = 1.18
    static let endCenterInsetMultiplier: CGFloat = 1.27
    static let safetyInset: CGFloat = 16

    let slot: CGFloat
    let longAxis: CGFloat
    let aspectRatio: CGFloat
    let providerCount: Int

    static func aspectRatio(providerCount: Int) -> CGFloat? {
        guard providerCount > 0 else { return nil }
        // The two 1.27S end insets and N - 1 provider pitches keep the
        // provider marks visually centred within the rail.
        return self.providerPitchMultiplier * CGFloat(providerCount) + 1.36
    }

    static func resolve(
        providerCount: Int,
        preferredSlot: CGFloat,
        availableLongAxis: CGFloat,
        backingScaleFactor: CGFloat = 2) -> Self?
    {
        guard let aspectRatio = Self.aspectRatio(providerCount: providerCount),
              availableLongAxis.isFinite,
              preferredSlot.isFinite,
              backingScaleFactor.isFinite,
              backingScaleFactor > 0
        else { return nil }

        let minimumSlot = 1 / backingScaleFactor
        let rawSlot = min(max(preferredSlot, 0), max(availableLongAxis, 0) / aspectRatio)
        let slot = floor(rawSlot * backingScaleFactor) / backingScaleFactor
        guard slot >= minimumSlot else { return nil }
        return Self(
            slot: slot,
            longAxis: aspectRatio * slot,
            aspectRatio: aspectRatio,
            providerCount: providerCount)
    }

    func contentBandCenter(for index: Int) -> CGFloat {
        self.slot * (Self.endCenterInsetMultiplier + Self.providerPitchMultiplier * CGFloat(index))
    }
}
