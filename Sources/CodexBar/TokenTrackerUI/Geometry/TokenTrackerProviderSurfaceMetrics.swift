import AppKit

struct TokenTrackerProviderSurfaceMetrics: Equatable, Sendable {
    // The three-provider shell follows the measured green reference frame
    // (164 x 717). Additional providers extend it by one established pitch.
    static let threeProviderAspectRatio: CGFloat = 717 / 164
    static let providerPitchMultiplier: CGFloat = 1.18
    static let safetyInset: CGFloat = 16

    let slot: CGFloat
    let longAxis: CGFloat
    let aspectRatio: CGFloat
    let providerCount: Int

    static func aspectRatio(providerCount: Int) -> CGFloat? {
        guard providerCount > 0 else { return nil }
        return self.threeProviderAspectRatio
            + self.providerPitchMultiplier * CGFloat(providerCount - 3)
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
        let providerBandLength = Self.providerPitchMultiplier * CGFloat(max(self.providerCount - 1, 0))
        let endCenterInset = (self.aspectRatio - providerBandLength) / 2
        return self.slot * (endCenterInset + Self.providerPitchMultiplier * CGFloat(index))
    }
}
