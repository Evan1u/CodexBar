import SwiftUI
import Testing
@testable import CodexBar

@Suite("Token Tracker edge protrusion shape")
struct TokenTrackerEdgeShapeTests {
    @Test
    func `side variants are continuous attached rounded rectangles and mirrored`() {
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 202)
        let left = TokenTrackerEdgeProtrusionShape(attachmentEdge: .left)
        let right = TokenTrackerEdgeProtrusionShape(attachmentEdge: .right)

        let leftBounds = left.path(in: bounds).boundingRect
        let rightBounds = right.path(in: bounds).boundingRect
        #expect(!left.path(in: bounds).isEmpty)
        #expect(!right.path(in: bounds).isEmpty)
        #expect(leftBounds.minX == bounds.minX)
        #expect(leftBounds.maxX == bounds.maxX)
        #expect(rightBounds.minX == bounds.minX)
        #expect(rightBounds.maxX == bounds.maxX)
        #expect(leftBounds.minY == rightBounds.minY)
        #expect(leftBounds.maxY == rightBounds.maxY)

        let mirroredLeft = left.path(in: bounds).applying(CGAffineTransform(
            a: -1,
            b: 0,
            c: 0,
            d: 1,
            tx: bounds.maxX,
            ty: bounds.minY))
        #expect(right.path(in: bounds).boundingRect == mirroredLeft.boundingRect)
    }

    @Test
    func `bottom variant is the rotated side outline`() {
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 118)
        let shape = TokenTrackerEdgeProtrusionShape(attachmentEdge: .bottom)

        let path = shape.path(in: bounds)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.minX >= bounds.minX)
        #expect(path.boundingRect.maxX <= bounds.maxX)
        #expect(path.boundingRect.minY >= bounds.minY)
        #expect(path.boundingRect.maxY <= bounds.maxY)
    }

    @Test
    func `side outline preserves a nonzero host rect origin`() {
        let bounds = CGRect(x: 37, y: 53, width: 64, height: 202)
        let left = TokenTrackerEdgeProtrusionShape(attachmentEdge: .left)
        let right = TokenTrackerEdgeProtrusionShape(attachmentEdge: .right)

        #expect(left.path(in: bounds).boundingRect == bounds)
        #expect(right.path(in: bounds).boundingRect == bounds)
    }

    @Test
    func `callout variants keep their arrow inside the rounded body clearance`() {
        let bounds = CGRect(x: 0, y: 0, width: 374, height: 240)
        let left = TokenTrackerProviderDetailCalloutShape(arrowEdge: .left, arrowOffset: 120)
        let right = TokenTrackerProviderDetailCalloutShape(arrowEdge: .right, arrowOffset: 120)
        let bottom = TokenTrackerProviderDetailCalloutShape(arrowEdge: .bottom, arrowOffset: 187)

        for path in [left.path(in: bounds), right.path(in: bounds), bottom.path(in: bounds)] {
            #expect(!path.isEmpty)
            #expect(path.boundingRect.minX >= bounds.minX)
            #expect(path.boundingRect.maxX <= bounds.maxX)
            #expect(path.boundingRect.minY >= bounds.minY)
            #expect(path.boundingRect.maxY <= bounds.maxY)
        }
        #expect(TokenTrackerCalloutGeometry.clampArrowOffset(-1, edgeLength: 240) == 28)
        #expect(TokenTrackerCalloutGeometry.clampArrowOffset(999, edgeLength: 240) == 212)
    }

    @Test
    func `arrow offset follows the screen coordinate anchor`() {
        let panel = CGRect(x: 100, y: 200, width: 374, height: 410)
        #expect(TokenTrackerCalloutGeometry.arrowOffset(
            logoCenter: CGPoint(x: 80, y: 500),
            panelFrame: panel,
            edge: .right) == 110)
        #expect(TokenTrackerCalloutGeometry.arrowOffset(
            logoCenter: CGPoint(x: 260, y: 280),
            panelFrame: panel,
            edge: .bottom) == 160)
        #expect(TokenTrackerCalloutGeometry.arrowOffset(
            logoCenter: CGPoint(x: 100, y: 700),
            panelFrame: panel,
            edge: .left) == 28)
    }
}
