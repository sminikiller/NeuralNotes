import XCTest
@testable import NeuralNotesCore

final class DraftingGuideRegressionTests: XCTestCase {
    func testBothStandardSquaresKeepEveryProjectedPointOnItsChosenEdge() throws {
        for kind in [RulerGuide.Kind.square45, .square60] {
            var guide = RulerGuide(x: 400, y: 500, angle: 0.31); guide.kind = kind; guide.length = 240
            let corners = guide.vertices
            XCTAssertEqual(corners.count, 3)
            for i in corners.indices {
                let a = corners[i], b = corners[(i + 1) % 3]
                let midpoint = StrokeSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let edge = guide.edge(nearest: midpoint)
                XCTAssertEqual(edge, Double(i))
                for raw in [StrokeSample(x: 10, y: 10), .init(x: 1500, y: -400), .init(x: 100, y: 900)] {
                    let result = try XCTUnwrap(guide.project(raw, edge: edge, width: 768, height: 1024))
                    let cross = (result.x - a.x) * (b.y - a.y) - (result.y - a.y) * (b.x - a.x)
                    XCTAssertEqual(cross, 0, accuracy: 0.0001)
                    XCTAssertTrue((0...768).contains(result.x)); XCTAssertTrue((0...1024).contains(result.y))
                }
            }
        }
    }
    func testSquareGeometryHasExactFortyFiveAndThirtySixtyAnglesAndRotatesWithoutDistortion() {
        var guide = RulerGuide(); guide.kind = .square45; guide.length = 300
        var points = guide.vertices
        XCTAssertEqual(hypot(points[1].x - points[0].x, points[1].y - points[0].y), 300, accuracy: 0.001)
        XCTAssertEqual(hypot(points[2].x - points[0].x, points[2].y - points[0].y), 300, accuracy: 0.001)
        guide.kind = .square60; guide.angle = .pi / 5; points = guide.vertices
        let short = hypot(points[2].x - points[0].x, points[2].y - points[0].y)
        let hypotenuse = hypot(points[2].x - points[1].x, points[2].y - points[1].y)
        XCTAssertEqual(hypotenuse, short * 2, accuracy: 0.001)
        guide.length = .nan; XCTAssertNil(guide.project(.init(x: 1, y: 1), edge: 0, width: 768, height: 1024))
    }
    func testLassoSelectsActualArcsAndAllPolygonKindsWithoutSelectingEmptyArcSpace() {
        for kind in [ShapeKind.arc, .triangle, .polygon, .star, .freePolygon, .diamond] {
            let shape = ShapeElement(kind: kind, x: 100, y: 100, width: 240, height: 180)
            let around = [StrokeSample(x: 80, y: 80), .init(x: 360, y: 80), .init(x: 360, y: 300), .init(x: 80, y: 300)]
            XCTAssertTrue(ShapeGeometry.intersects(shape, selection: around), "\(kind)")
            let outside = [StrokeSample(x: 450, y: 450), .init(x: 470, y: 450), .init(x: 470, y: 470), .init(x: 450, y: 470)]
            XCTAssertFalse(ShapeGeometry.intersects(shape, selection: outside), "\(kind)")
        }
        var arc = ShapeElement(kind: .arc, x: 100, y: 100, width: 200, height: 200)
        arc.arcStart = 0; arc.arcSweep = .pi
        let contour = ShapeGeometry.polylines(ShapeGeometry.path(for: arc), steps: 64)[0]
        let p = contour[contour.count / 2]
        let small = [StrokeSample(x: p.x - 8, y: p.y - 8), .init(x: p.x + 8, y: p.y - 8), .init(x: p.x + 8, y: p.y + 8), .init(x: p.x - 8, y: p.y + 8)]
        XCTAssertTrue(ShapeGeometry.intersects(arc, selection: small))
        let emptyCenter = [StrokeSample(x: 190, y: 190), .init(x: 210, y: 190), .init(x: 210, y: 210), .init(x: 190, y: 210)]
        XCTAssertFalse(ShapeGeometry.intersects(arc, selection: emptyCenter))
    }
}
