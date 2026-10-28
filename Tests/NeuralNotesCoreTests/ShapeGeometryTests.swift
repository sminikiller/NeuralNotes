import XCTest
@testable import NeuralNotesCore

final class ShapeGeometryTests: XCTestCase {
    func testEveryShapeProducesFiniteSharedGeometryAndValidOptions() throws {
        for kind in ShapeKind.allCases {
            var shape = ShapeElement(kind: kind); shape.sides = kind == .star ? 5 : 6
            shape.innerRatio = 0.5
            let points = ShapeGeometry.polylines(ShapeGeometry.path(for: shape)).flatMap { $0 }
            XCTAssertGreaterThan(points.count, 1, kind.rawValue)
            XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            var page = PageSnapshot(); page.shapes = [shape]; XCTAssertNoThrow(try PageValidation.validate(page))
        }
    }
    func testPolygonStarAndRoundedCorners() {
        var polygon = ShapeElement(kind: .polygon); polygon.sides = 7
        XCTAssertEqual(ShapeGeometry.polylines(ShapeGeometry.path(for: polygon))[0].count, 8)
        polygon.kind = .star; polygon.sides = 5; polygon.innerRatio = 0.4
        XCTAssertEqual(ShapeGeometry.polylines(ShapeGeometry.path(for: polygon))[0].count, 11)
        polygon.kind = .rectangle; polygon.cornerRadius = 10
        XCTAssertTrue(ShapeGeometry.path(for: polygon).commands.contains { if case .quad = $0 { return true }; return false })
    }
    func testFilledAndOutlineHitTestingUsesScreenToleranceAtAnyZoom() {
        var shape = ShapeElement(kind: .ellipse, x: 10, y: 20, width: 100, height: 60)
        XCTAssertFalse(ShapeGeometry.hit(.init(x: 60, y: 50), shape: shape, zoom: 1))
        shape.fill = .red
        XCTAssertTrue(ShapeGeometry.hit(.init(x: 60, y: 50), shape: shape, zoom: 4))
        shape.fill = nil
        XCTAssertTrue(ShapeGeometry.hit(.init(x: 116, y: 50), shape: shape, zoom: 1))
        XCTAssertFalse(ShapeGeometry.hit(.init(x: 116, y: 50), shape: shape, zoom: 4))
        shape.rotation = 90
        XCTAssertTrue(ShapeGeometry.hit(.init(x: 60, y: 100), shape: shape, zoom: 2))
    }
    func testDirectionalArrowsAndDashPatterns() throws {
        var shape = try XCTUnwrap(ShapeElement.dragged(kind: .arrow, from: .init(x: 200, y: 50), to: .init(x: 20, y: 160), color: .blue, lineWidth: 4))
        shape.arrowHeads = .both; shape.arrowStyle = .filled
        XCTAssertEqual(ShapeGeometry.arrowPaths(for: shape).count, 2)
        XCTAssertEqual(ShapeDash.dashed.lengths(width: 4), [12, 8]); XCTAssertEqual(ShapeDash.dotted.lengths(width: 4), [0, 8])
        let paths = ShapeGeometry.polylines(ShapeGeometry.path(for: shape))
        XCTAssertEqual(paths.first?.first?.x, 200); XCTAssertEqual(paths.first?.last?.x, 20)
    }
    func testArcCurvatureKeepsBothChordEndpoints() throws {
        let arc = try XCTUnwrap(ShapeElement.dragged(kind: .arc, from: .init(x: 50, y: 150), to: .init(x: 250, y: 150), color: .black, lineWidth: 3))
        let changed = ShapeHandles.moved(arc, handle: .arcCurvature, to: .init(x: 150, y: 110))
        for handle in [ShapeHandle.start, .end] {
            let a = try XCTUnwrap(ShapeHandles.positions(arc, zoom: 1).first(where: { $0.0 == handle })?.1)
            let b = try XCTUnwrap(ShapeHandles.positions(changed, zoom: 1).first(where: { $0.0 == handle })?.1)
            XCTAssertEqual(a.x, b.x, accuracy: 0.001); XCTAssertEqual(a.y, b.y, accuracy: 0.001)
        }
        XCTAssertNotEqual(changed.arcSweep, arc.arcSweep); XCTAssertTrue(changed.hasValidOptions)
    }
    func testHandlesRotationInnerRadiusAndInvalidCoordinates() {
        var star = ShapeElement(kind: .star); star.sides = 5
        let changed = ShapeHandles.moved(star, handle: .innerRadius, to: .init(x: 10_000, y: 10_000))
        XCTAssertEqual(changed.innerRatio, 0.8)
        XCTAssertEqual(ShapeHandles.moved(star, handle: .end, to: .init(x: .nan, y: 20)), star)
        let rotated = ShapeHandles.moved(star, handle: .rotation, to: .init(x: star.x + star.width, y: star.y + star.height / 2))
        XCTAssertEqual(rotated.rotation, 90)
    }
    func testValidationRejectsBadNewFieldsButAcceptsLegacyThinContours() {
        var page = PageSnapshot(); var shape = ShapeElement(kind: .rectangle, lineWidth: 0.1)
        page.shapes = [shape]; XCTAssertNoThrow(try PageValidation.validate(page))
        for bad in [Double.nan, -.infinity, 1.1] {
            shape.fillOpacity = bad; page.shapes = [shape]; XCTAssertThrowsError(try PageValidation.validate(page))
        }
        shape.fillOpacity = nil; shape.vertices = [.init(x: 0, y: 0), .init(x: 0, y: 0), .init(x: 1, y: 1)]
        page.shapes = [shape]; XCTAssertThrowsError(try PageValidation.validate(page))
    }
    func testFreeVertexCanMoveOutsideTheOriginalBoxWithoutMovingOtherVertices() throws {
        var shape = ShapeElement(kind: .freePolygon, x: 100, y: 100, width: 200, height: 100)
        shape.rotation = 30
        let before = ShapeHandles.positions(shape, zoom: 1)
        let target = ShapeGeometry.rotate(.init(x: 40, y: 60), shape: shape)
        let changed = ShapeHandles.moved(shape, handle: .vertex(0), to: target)
        let after = ShapeHandles.positions(changed, zoom: 1)
        for index in 0..<4 {
            let expected: StrokeSample
            if index == 0 { expected = target }
            else { expected = try XCTUnwrap(before.first { $0.0 == .vertex(index) }?.1) }
            let actual = try XCTUnwrap(after.first { $0.0 == .vertex(index) }?.1)
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.001)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.001)
        }
        XCTAssertTrue(changed.hasValidOptions)
    }
    func testUnknownRecognitionKindsDoNotInvalidateWorkspacePreferences() throws {
        let data = Data(#"{"enabledKinds":["future-a","future-b","line"]}"#.utf8)
        let value = try JSONDecoder().decode(ShapePreferences.self, from: data)
        XCTAssertTrue(value.isValid); XCTAssertEqual(value.kinds, [.rectangle, .line])
    }
    func testUnknownKindsAndStylesFallBackWithoutLosingThePage() throws {
        var page = PageSnapshot(); page.shapes = [ShapeElement(kind: .star)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        var shapes = try XCTUnwrap(object["shapes"] as? [[String: Any]])
        shapes[0]["kind"] = "future-hypercube"; shapes[0]["dash"] = "future-dash"; shapes[0]["arrowStyle"] = "future-arrow"
        object["shapes"] = shapes
        let restored = try JSONDecoder().decode(PageSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.shapes?.first?.kind, .rectangle); XCTAssertEqual(restored.shapes?.first?.dash, .solid)
        XCTAssertEqual(restored.shapes?.first?.arrowStyle, .open); XCTAssertNoThrow(try PageValidation.validate(restored))
    }
    func testDragSnapsAngleAndProportions() {
        let diagonal = ShapeSnapping.drag(kind: .line, start: .init(x: 0, y: 0), end: .init(x: 100, y: 26))
        XCTAssertTrue(diagonal.angleSnapped)
        let angle = atan2(diagonal.end.y, diagonal.end.x) * 180 / .pi
        XCTAssertEqual(angle, 15, accuracy: 0.001)
        let square = ShapeSnapping.drag(kind: .rectangle, start: .init(x: 50, y: 50), end: .init(x: 150, y: 147))
        XCTAssertTrue(square.proportionsSnapped); XCTAssertEqual(square.end.x, square.end.y)
    }
    func testConnectionIndexIsZoomAwareWithThousandsOfCandidates() {
        let points = (0..<4000).map { StrokeSample(x: Double($0 % 100) * 50, y: Double($0 / 100) * 50) }
        let index = ShapeConnectionIndex(points: points)
        XCTAssertEqual(index.nearest(.init(x: 103, y: 102), zoom: 1), .init(x: 100, y: 100))
        XCTAssertNil(index.nearest(.init(x: 103, y: 102), zoom: 4))
        XCTAssertNil(index.nearest(.init(x: .infinity, y: 0), zoom: 1))
        let start = Date()
        for _ in 0..<200 { XCTAssertNotNil(index.nearest(.init(x: 103, y: 102), zoom: 1)) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
    }
}
