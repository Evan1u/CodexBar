import Foundation

enum TokenTrackerDetailSizing {
    static let bodyWidth: CGFloat = 360
    static let arrowLength: CGFloat = 14
    static let maximumBodyHeight: CGFloat = 400
    static let screenVerticalInset: CGFloat = 24
    static let initialBodyHeight: CGFloat = 220

    static func bodyHeight(fittingHeight: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        let maximum = min(
            self.maximumBodyHeight,
            max(visibleHeight - self.screenVerticalInset, 0))
        guard maximum > 0 else { return 0 }
        let safeFittingHeight = fittingHeight.isFinite ? max(fittingHeight, 0) : 0
        return min(safeFittingHeight, maximum)
    }

    static func initialBodyHeight(visibleHeight: CGFloat) -> CGFloat {
        min(self.initialBodyHeight, max(visibleHeight - self.screenVerticalInset, 0))
    }

    static func sideSize(bodyHeight: CGFloat) -> CGSize {
        CGSize(width: self.bodyWidth + self.arrowLength, height: bodyHeight)
    }

    static func bottomSize(bodyHeight: CGFloat) -> CGSize {
        CGSize(width: self.bodyWidth, height: bodyHeight + self.arrowLength)
    }
}
