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

        let expectedAspectRatio = 717 / CGFloat(164) + 1.18 * CGFloat(providerCount - 3)
        let expectedEndInset = (expectedAspectRatio - 1.18 * CGFloat(providerCount - 1)) / 2
        #expect(abs(metrics.aspectRatio - expectedAspectRatio) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: 0) - expectedEndInset * metrics.slot) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: providerCount - 1) -
                (metrics.longAxis - expectedEndInset * metrics.slot)) < 0.001)
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

        #expect(abs(three.aspectRatio - 4.371951) < 0.001)
        #expect(abs(three.longAxis - 279.804878) < 0.001)
        #expect(abs(four.aspectRatio - 5.551951) < 0.001)
        #expect(abs(four.longAxis - three.longAxis - 75.52) < 0.001)
    }

    @Test
    func `constrained surface reduces every dimension uniformly without scrolling`() throws {
        let metrics = try #require(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 4,
            preferredSlot: 64,
            availableLongAxis: 256,
            backingScaleFactor: 2))

        #expect(metrics.slot == 46)
        #expect(abs(metrics.longAxis - 255.389756) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: 0) - 46.274878) < 0.001)
        #expect(abs(metrics.contentBandCenter(for: 3) - 209.114878) < 0.001)
        #expect(TokenTrackerProviderSurfaceMetrics.resolve(
            providerCount: 4,
            preferredSlot: 64,
            availableLongAxis: 2.7,
            backingScaleFactor: 2) == nil)
    }
}
