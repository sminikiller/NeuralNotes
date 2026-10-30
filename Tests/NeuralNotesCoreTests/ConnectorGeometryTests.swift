import XCTest
@testable import NeuralNotesCore

final class ConnectorGeometryTests: XCTestCase {
    func testAreaSelectionIntersectsTheLineButNotTheEmptyCornerOfItsBounds() {
        let edge = ConnectorElement(from: .init(x: 100, y: 100), to: .init(x: 300, y: 300), routing: .straight)
        let center: [StrokeSample] = [.init(x: 195, y: 195), .init(x: 205, y: 195), .init(x: 205, y: 205), .init(x: 195, y: 205)]
        let emptyCorner = center.map { StrokeSample(x: $0.x, y: $0.y - 90) }
        XCTAssertTrue(ConnectorGeometry.intersects(edge, objects: [:], selection: center))
        XCTAssertFalse(ConnectorGeometry.intersects(edge, objects: [:], selection: emptyCorner))
    }
    func testQuickBlockDirectionFollowsTheRotatedConnectionPoint() throws {
        let box = SnapRect(x: 300, y: 350, width: 160, height: 160), page = SnapRect(x: 0, y: 0, width: 1024, height: 1024)
        let direction = StrokeSample(x: -sqrt(0.5), y: -sqrt(0.5))
        let copy = try XCTUnwrap(QuickDiagramLayout.duplicate(box, direction: direction, page: page, obstacles: [box]))
        XCTAssertLessThan(copy.midX, box.midX); XCTAssertLessThan(copy.midY, box.midY)
        XCTAssertEqual((copy.midX - box.midX) / (copy.midY - box.midY), 1, accuracy: 0.001)
        let projectedGap = hypot(copy.midX - box.midX, copy.midY - box.midY) - sqrt(0.5) * 320
        XCTAssertEqual(projectedGap, 48, accuracy: 0.001)
    }
    func testSpatialTargetsAreOrderedAndOversizedObjectsDoNotExpandTheGrid() {
        let base = UUID(), middle = UUID(), top = UUID()
        let boxes = [base: SnapRect(x: 0, y: 0, width: 20_000, height: 20_000),
                     middle: SnapRect(x: 100, y: 100, width: 120, height: 100), top: SnapRect(x: 130, y: 130, width: 80, height: 60)]
        let index = ConnectorTargetIndex(boxes: boxes, order: [base, middle, top])
        XCTAssertEqual(index.candidates(at: .init(x: 160, y: 160), zoom: 2), [top, middle, base])
        XCTAssertEqual(index.candidates(at: .init(x: 10_000, y: 10_000), zoom: 1), [base])
        XCTAssertTrue(index.candidates(at: .init(x: .nan, y: 0), zoom: 1).isEmpty)
    }
    func testTargetQueriesOnFiveThousandBlocksStayWithinAFrameBudget() {
        var boxes: [UUID: SnapRect] = [:], order: [UUID] = []
        for i in 0..<5000 {
            let id = UUID(); order.append(id)
            boxes[id] = .init(x: Double(i % 100) * 200, y: Double(i / 100) * 160, width: 120, height: 100)
        }
        let index = ConnectorTargetIndex(boxes: boxes, order: order), start = Date()
        for i in 0..<2000 {
            let point = StrokeSample(x: Double(i % 100) * 200 + 60, y: Double(i / 100) * 160 + 50)
            XCTAssertEqual(index.candidates(at: point, zoom: 2).first, order[i])
        }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 2000, 0.016, "Budget del runner, non una misura fisica dei fps dell’iPad.")
    }
    func testRotatedContoursAttachAtTheNearestPointAndFollowGeometryChanges() throws {
        for kind in [ShapeKind.rectangle, .ellipse, .diamond, .polygon, .star, .triangle] {
            var shape = ShapeElement(kind: kind, x: 100, y: 150, width: 160, height: 160)
            shape.rotation = 33
            let object = ConnectorObject(shape: shape)
            let point = object.rotate(.init(x: shape.x + shape.width + 5, y: shape.y + 64))
            let end = try XCTUnwrap(object.closest(point, zoom: 2, magnet: false))
            XCTAssertEqual(end.objectID, shape.id); XCTAssertTrue(end.anchor.isValid)
            let resolved = ConnectorGeometry.resolve(end, objects: [shape.id: object])
            XCTAssertEqual(resolved.x, end.x, accuracy: 0.001); XCTAssertEqual(resolved.y, end.y, accuracy: 0.001)
            var boundary = shape; boundary.fill = nil
            XCTAssertTrue(ShapeGeometry.hit(resolved, shape: boundary, zoom: 2, tolerance: 0.1), "\(kind)")
            shape.x += 90; shape.width *= 1.2; shape.rotation = 67
            let moved = ConnectorObject(shape: shape), newPosition = ConnectorGeometry.resolve(end, objects: [shape.id: moved])
            let expected = moved.point(at: end.anchor)
            XCTAssertEqual(newPosition.x, expected.x, accuracy: 0.001); XCTAssertEqual(newPosition.y, expected.y, accuracy: 0.001)
            XCTAssertGreaterThan(hypot(resolved.x - newPosition.x, resolved.y - newPosition.y), 20)
        }
    }
    func testMidpointMagnetUsesScreenDistanceAndLockedTargetsAreExcluded() throws {
        let id = UUID(), object = ConnectorObject(id: id, rect: .init(x: 100, y: 100, width: 200, height: 100))
        let near = StrokeSample(x: 207, y: 96)
        let magnet = try XCTUnwrap(object.closest(near, zoom: 1))
        XCTAssertEqual(magnet.anchor, .init(x: 0.5, y: 0))
        let free = try XCTUnwrap(object.closest(near, zoom: 2))
        XCTAssertNotEqual(free.anchor, magnet.anchor)
        var locked = object; locked.locked = true; XCTAssertNil(locked.closest(near, zoom: 1))
    }
    func testDeletionDetachesAtLatestPositionRatherThanCreationFallback() throws {
        var page = PageSnapshot(), shape = ShapeElement(kind: .rectangle, x: 40, y: 50, width: 100, height: 80)
        let end = ConnectorObject(shape: shape).end(at: .init(x: 140, y: 90))
        page.shapes = [shape]; page.connectors = [.init(from: end, to: .init(x: 400, y: 200))]
        shape.x = 300; shape.rotation = 90; page.shapes = [shape]
        let expected = ConnectorGeometry.resolve(end, objects: page.connectorObjects())
        page.refreshConnectorFallbacks(objects: page.connectorObjects())
        page.shapes = []; page.pruneObjectReferences()
        let detached = try XCTUnwrap(page.connectors?.first?.from)
        XCTAssertNil(detached.objectID); XCTAssertEqual(detached.x, expected.x, accuracy: 0.001); XCTAssertEqual(detached.y, expected.y, accuracy: 0.001)
        XCTAssertNoThrow(try PageValidation.validate(page))
    }
    func testAllOrthogonalSidePairsAvoidTheConnectedObjectsAndExitNormally() throws {
        let a = ConnectorObject(shape: ShapeElement(kind: .rectangle, x: 100, y: 120, width: 140, height: 100))
        let b = ConnectorObject(shape: ShapeElement(kind: .rectangle, x: 400, y: 350, width: 160, height: 120))
        let objects = [a.id: a, b.id: b]
        for first in a.connectionPoints { for last in b.connectionPoints {
            let connector = ConnectorElement(from: a.end(at: first), to: b.end(at: last), routing: .elbow)
            let line = try XCTUnwrap(ShapeGeometry.polylines(ConnectorGeometry.path(connector, objects: objects)).first)
            XCTAssertEqual(line.first, first); XCTAssertEqual(line.last, last)
            for i in 1..<line.count {
                let p = line[i - 1], q = line[i]
                XCTAssertTrue(abs(p.x - q.x) < 0.001 || abs(p.y - q.y) < 0.001)
                for k in 1..<20 {
                    let t = Double(k) / 20, sample = StrokeSample(x: p.x + t * (q.x - p.x), y: p.y + t * (q.y - p.y))
                    for r in [a.rect, b.rect] {
                        let interior = sample.x > r.x + 0.01 && sample.x < r.maxX - 0.01 && sample.y > r.y + 0.01 && sample.y < r.maxY - 0.01
                        XCTAssertFalse(interior, "Il connettore attraversa un blocco")
                    }
                }
            }
            let n = a.normal(at: first), next = try XCTUnwrap(line.dropFirst().first)
            XCTAssertGreaterThan((next.x - first.x) * n.x + (next.y - first.y) * n.y, 0)
        } }
    }
    func testCurvedMidpointAndHitUseTheActualPathRatherThanItsBoundingBox() {
        var c = ConnectorElement(from: .init(x: 100, y: 100), to: .init(x: 300, y: 100))
        c.controlPoints = [.init(x: 100, y: 300), .init(x: 300, y: 300)]
        let center = ConnectorGeometry.midpoint(c, objects: [:])
        XCTAssertEqual(center.x, 200, accuracy: 0.1); XCTAssertEqual(center.y, 250, accuracy: 0.1)
        XCTAssertTrue(ConnectorGeometry.hit(center, connector: c, objects: [:], zoom: 1))
        XCTAssertFalse(ConnectorGeometry.hit(.init(x: 200, y: 110), connector: c, objects: [:], zoom: 1))
    }
    func testCopyRemapsInternalReferencesAndDetachesOutsideTargets() throws {
        var page = PageSnapshot()
        let a = ShapeElement(kind: .rectangle), b = ShapeElement(kind: .ellipse, x: 300)
        let c = ConnectorElement(from: ConnectorObject(shape: a).end(at: .init(x: 240, y: 180)), to: ConnectorObject(shape: b).end(at: .init(x: 300, y: 180)))
        page.shapes = [a, b]; page.connectors = [c]; page.objectOrder = [c.id, a.id, b.id]
        XCTAssertEqual(page.includingInternalConnectors([a.id, b.id]), [a.id, b.id, c.id])
        let map = page.renewObjectIDs()
        XCTAssertEqual(page.connectors?.first?.from.objectID, map[a.id]); XCTAssertEqual(page.connectors?.first?.to.objectID, map[b.id])
        XCTAssertEqual(page.objectOrder, [map[c.id]!, map[a.id]!, map[b.id]!]); XCTAssertNoThrow(try PageValidation.validate(page))
        page.shapes?.removeLast(); page.pruneObjectReferences(); XCTAssertNil(page.connectors?.first?.to.objectID)
        XCTAssertNotNil(page.connectors?.first?.from.objectID)
    }
    func testUnknownRoutingMissingTargetsAndMalformedGeometryAreSafe() throws {
        var page = PageSnapshot(); page.connectors = [.init(from: .init(objectID: UUID(), x: 12, y: 34), to: .init(x: 100, y: 200))]
        var json = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"curved\"", with: "\"futureRouting\"")
        var decoded = try JSONDecoder().decode(PageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.connectors?.first?.routing, .straight)
        let end = try XCTUnwrap(decoded.connectors?.first?.from)
        XCTAssertEqual(ConnectorGeometry.resolve(end, objects: [:]), .init(x: 12, y: 34))
        decoded.pruneObjectReferences(); XCTAssertNil(decoded.connectors?.first?.from.objectID)
        XCTAssertNoThrow(try PageValidation.validate(decoded))
        decoded.connectors?[0].from.x = .infinity; XCTAssertThrowsError(try PageValidation.validate(decoded))
        decoded.connectors = [page.connectors![0], page.connectors![0]]; XCTAssertThrowsError(try PageValidation.validate(decoded))
    }
    func testVerticalOpenShapeKeepsAReadableCenteredLabelRegion() {
        let line = ShapeElement(kind: .line, x: 150, y: 100, width: 1, height: 300)
        let region = ShapeLabelRegion.rect(line)
        XCTAssertEqual(region.midX, 150.5); XCTAssertEqual(region.midY, 250)
        XCTAssertEqual(region.width, 80); XCTAssertEqual(region.height, 48)
    }
    func testQuickBlocksAvoidOverlapAndStayOnPageAndSafeLabelRegionsFit() throws {
        let page = SnapRect(x: 0, y: 0, width: 768, height: 1024), source = SnapRect(x: 40, y: 100, width: 160, height: 100)
        let copy = try XCTUnwrap(QuickDiagramLayout.duplicate(source, side: .right, page: page, obstacles: [source]))
        XCTAssertEqual(copy.x - source.maxX, 48); XCTAssertEqual(copy.y, source.y)
        let alternate = try XCTUnwrap(QuickDiagramLayout.duplicate(source, side: .right, page: page, obstacles: [source, copy]))
        XCTAssertNotEqual(copy, alternate); XCTAssertGreaterThanOrEqual(alternate.x, 8); XCTAssertLessThanOrEqual(alternate.maxX, 760)
        for kind in [ShapeKind.rectangle, .ellipse, .diamond, .polygon, .star, .triangle, .freePolygon] {
            let shape = ShapeElement(kind: kind, x: 100, y: 100, width: 200, height: 200), rect = ShapeLabelRegion.rect(shape)
            let outline = try XCTUnwrap(ShapeGeometry.polylines(ShapeGeometry.path(for: shape)).first)
            for p in [StrokeSample(x: rect.x, y: rect.y), .init(x: rect.maxX, y: rect.y), .init(x: rect.maxX, y: rect.maxY), .init(x: rect.x, y: rect.maxY)] {
                XCTAssertTrue(ShapeGeometry.contains(p, polygon: outline), "\(kind)")
            }
        }
    }
}
