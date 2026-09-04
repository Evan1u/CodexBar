import AppKit
import Testing
@testable import CodexBar

@Suite("Token Tracker provider surface metrics")
struct TokenTrackerProviderSurfaceMetricsTests {
    @Test(arguments: [1, 3, 4, 10])
    func `every provider count keeps the proportional band geometry`(providerCount: Int) throws {
        let metrics = try #require(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: providerCount,
            preferredSlot: 64,
            availableLongAxis: 2000))

        #expect(abs(metrics.aspectRatio - (1.18 * CGFloat(providerCount) + 1.36)) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: 0) - 1.27 * metrics.slot) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: providerCount - 1) -
                (metrics.longAxis - 1.27 * metrics.slot)) < 0.001)
        #expect(metrics.contentBandCenter(for: providerCount - 1) <= metrics.longAxis)
    }

    @Test
    func `proportional ratio grows by one provider pitch`() throws {
        let three = try #require(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 3,
            preferredSlot: 64,
            availableLongAxis: 800))
        let four = try #require(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 4,
            preferredSlot: 64,
            availableLongAxis: 800))

        #expect(abs(three.aspectRatio - 4.9) < 0.001)
        #expect(abs(three.longAxis - 313.6) < 0.001)
        #expect(abs(four.aspectRatio - 6.08) < 0.001)
        #expect(abs(four.longAxis - three.longAxis - 75.52) < 0.001)
    }

    @Test
    func `constrained surface reduces every dimension uniformly without scrolling`() throws {
        let metrics = try #require(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 4,
            preferredSlot: 64,
            availableLongAxis: 256,
            backingScaleFactor: 2))

        #expect(metrics.slot == 42)
        #expect(abs(metrics.longAxis - 255.36) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: 0) - 53.34) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: 3) - 202.02) < 0.001)
        #expect(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 4,
            preferredSlot: 64,
            availableLongAxis: 2.7,
            backingScaleFactor: 2) == nil)
    }
}
